defmodule CozyCheckout.GuestEmails do
  @moduledoc """
  Dispatches individually addressed booking emails through Oban.
  """

  import Ecto.Query

  alias CozyCheckout.GuestEmails.TemplateCatalog
  alias CozyCheckout.Repo
  alias CozyCheckout.Workers.BookingEmailWorker

  @email_regex ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  def configured? do
    mailer_config = Application.get_env(:cozy_checkout, CozyCheckout.Mailer, [])

    case Keyword.get(mailer_config, :adapter) do
      Swoosh.Adapters.Resend ->
        case Keyword.get(mailer_config, :api_key) do
          key when is_binary(key) -> String.trim(key) != ""
          _key -> false
        end

      _adapter ->
        true
    end
  end

  def valid_email?(email) when is_binary(email), do: Regex.match?(@email_regex, email)
  def valid_email?(_email), do: false

  def enqueue_batch(template_id, subject, deliveries) when is_binary(template_id) do
    enqueue_batch(%{type: :template, template_id: template_id}, subject, deliveries)
  end

  def enqueue_batch(%{type: :template, template_id: template_id} = content, subject, deliveries)
      when is_binary(template_id) and is_binary(subject) and is_list(deliveries) do
    with {:ok, rendered} <- TemplateCatalog.render(template_id) do
      enqueue_rendered_batch(content, rendered, subject, deliveries)
    end
  end

  def enqueue_batch(%{type: :custom, body: body} = content, subject, deliveries)
      when is_binary(body) and is_binary(subject) and is_list(deliveries) do
    with {:ok, rendered} <- TemplateCatalog.render_custom(body) do
      enqueue_rendered_batch(content, rendered, subject, deliveries)
    end
  end

  def enqueue_batch(_content, _subject, _deliveries), do: {:error, :invalid_request}

  defp enqueue_rendered_batch(content, rendered, subject, deliveries) do
    with :ok <- validate_subject(subject),
         :ok <- validate_deliveries(deliveries) do
      batch_id = Ecto.UUID.generate()

      result =
        Repo.transaction(fn ->
          Enum.map(deliveries, fn delivery ->
            args =
              delivery
              |> Map.take([:booking_id, :booking_name, :recipient_email])
              |> Map.merge(%{
                batch_id: batch_id,
                content_mode: content.type,
                html_body: rendered.html,
                text_body: rendered.text,
                subject: String.trim(subject)
              })
              |> maybe_put_template_id(content)

            case args |> BookingEmailWorker.new() |> Oban.insert() do
              {:ok, job} -> job
              {:error, reason} -> Repo.rollback(reason)
            end
          end)
        end)

      case result do
        {:ok, jobs} -> {:ok, %{batch_id: batch_id, jobs: jobs}}
        {:error, reason} -> {:error, {:enqueue_failed, reason}}
      end
    end
  end

  defp maybe_put_template_id(args, %{type: :template, template_id: template_id}),
    do: Map.put(args, :template_id, template_id)

  defp maybe_put_template_id(args, _content), do: args

  def list_batch_jobs(batch_id) when is_binary(batch_id) do
    from(job in Oban.Job,
      where: fragment("? ->> 'batch_id' = ?", job.args, ^batch_id),
      order_by: [asc: job.inserted_at]
    )
    |> Repo.all()
  end

  defp validate_subject(subject) do
    if String.trim(subject) != "" and String.length(subject) <= 255 do
      :ok
    else
      {:error, :invalid_subject}
    end
  end

  defp validate_deliveries([]), do: {:error, :no_recipients}

  defp validate_deliveries(deliveries) do
    if Enum.all?(deliveries, fn delivery ->
         is_map(delivery) and valid_email?(Map.get(delivery, :recipient_email)) and
           is_binary(Map.get(delivery, :booking_id)) and
           is_binary(Map.get(delivery, :booking_name))
       end) do
      :ok
    else
      {:error, :invalid_recipient}
    end
  end
end
