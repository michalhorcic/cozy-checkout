defmodule CozyCheckout.GuestEmails do
  @moduledoc """
  Dispatches individually addressed booking emails through Oban.
  """

  import Ecto.Query

  alias CozyCheckout.GuestEmails.TemplateCatalog
  alias CozyCheckout.GuestEmails.Delivery
  alias CozyCheckout.Bookings.Booking
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
    enqueue_rendered_batch(content, subject, deliveries)
  end

  def enqueue_batch(%{type: :custom, body: body} = content, subject, deliveries)
      when is_binary(body) and is_binary(subject) and is_list(deliveries) do
    with {:ok, rendered} <- TemplateCatalog.render_custom(body) do
      enqueue_rendered_batch(content, subject, deliveries, rendered)
    end
  end

  def enqueue_batch(_content, _subject, _deliveries), do: {:error, :invalid_request}

  defp enqueue_rendered_batch(content, subject, deliveries, custom_rendered \\ nil) do
    with :ok <- validate_subject(subject),
         :ok <- validate_deliveries(deliveries),
         {:ok, prepared_deliveries} <-
           prepare_deliveries(content, subject, deliveries, custom_rendered) do
      batch_id = Ecto.UUID.generate()

      result =
        Repo.transaction(fn ->
          Enum.map(prepared_deliveries, fn delivery ->
            {:ok, email_delivery} =
              delivery
              |> Map.take([
                :booking_id,
                :booking_name,
                :recipient_email,
                :subject,
                :content_mode,
                :template_id
              ])
              |> Map.merge(%{batch_id: batch_id, state: "queued"})
              |> then(&Delivery.changeset(%Delivery{}, &1))
              |> Repo.insert()

            args =
              delivery
              |> Map.take([
                :booking_id,
                :booking_name,
                :recipient_email,
                :subject,
                :html_body,
                :text_body
              ])
              |> Map.merge(%{
                batch_id: batch_id,
                content_mode: Atom.to_string(content.type),
                delivery_id: email_delivery.id
              })
              |> maybe_put_template_id(content)

            case args |> BookingEmailWorker.new() |> Oban.insert() do
              {:ok, job} ->
                email_delivery
                |> Delivery.changeset(%{oban_job_id: job.id})
                |> Repo.update!()

                job

              {:error, reason} ->
                Repo.rollback(reason)
            end
          end)
        end)

      case result do
        {:ok, jobs} -> {:ok, %{batch_id: batch_id, jobs: jobs}}
        {:error, reason} -> {:error, {:enqueue_failed, reason}}
      end
    end
  end

  defp prepare_deliveries(content, subject, deliveries, custom_rendered) do
    booking_ids = Enum.map(deliveries, & &1.booking_id) |> Enum.uniq()

    bookings =
      from(booking in Booking,
        join: guest in assoc(booking, :guest),
        where: booking.id in ^booking_ids,
        preload: [guest: guest]
      )
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    Enum.reduce_while(deliveries, {:ok, []}, fn delivery, {:ok, prepared} ->
      case Map.fetch(bookings, delivery.booking_id) do
        {:ok, booking} ->
          rendered =
            case content.type do
              :template ->
                TemplateCatalog.render(
                  content.template_id,
                  booking,
                  subject,
                  Map.get(delivery, :greeting_name)
                )

              :custom ->
                {:ok, Map.put(custom_rendered, :subject, String.trim(subject))}
            end

          case rendered do
            {:ok, email_content} ->
              if valid_subject?(email_content.subject) do
                item =
                  Map.merge(delivery, %{
                    booking_name: booking.guest.name,
                    subject: email_content.subject,
                    html_body: email_content.html,
                    text_body: email_content.text,
                    content_mode: Atom.to_string(content.type),
                    template_id: Map.get(content, :template_id)
                  })

                {:cont, {:ok, [item | prepared]}}
              else
                {:halt, {:error, :invalid_subject}}
              end

            {:error, reason} ->
              {:halt, {:error, reason}}
          end

        :error ->
          {:halt, {:error, {:booking_not_found, delivery.booking_id}}}
      end
    end)
    |> case do
      {:ok, prepared} -> {:ok, Enum.reverse(prepared)}
      error -> error
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

  def list_booking_deliveries(booking_id) when is_binary(booking_id) do
    from(delivery in Delivery,
      where: delivery.booking_id == ^booking_id,
      order_by: [desc: delivery.inserted_at]
    )
    |> Repo.all()
  end

  def mark_sending(nil, _attempt), do: :ok

  def mark_sending(delivery_id, attempt) do
    delivery = Repo.get!(Delivery, delivery_id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    delivery
    |> Delivery.changeset(%{
      state: "sending",
      attempt_count: attempt,
      started_at: delivery.started_at || now,
      completed_at: nil,
      last_error: nil
    })
    |> Repo.update!()

    :ok
  end

  def mark_accepted(nil), do: :ok

  def mark_accepted(delivery_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    update_delivery!(delivery_id, %{
      state: "accepted",
      accepted_at: now,
      completed_at: now,
      last_error: nil
    })
  end

  def mark_retrying(nil, _reason), do: :ok

  def mark_retrying(delivery_id, reason) do
    update_delivery!(delivery_id, %{
      state: "retrying",
      completed_at: nil,
      last_error: delivery_error(reason)
    })
  end

  def mark_failed(nil, _reason), do: :ok

  def mark_failed(delivery_id, reason) do
    update_delivery!(delivery_id, %{
      state: "failed",
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      last_error: delivery_error(reason)
    })
  end

  defp update_delivery!(delivery_id, attrs) do
    Delivery
    |> Repo.get!(delivery_id)
    |> Delivery.changeset(attrs)
    |> Repo.update!()

    :ok
  end

  defp delivery_error({status, _reason}) when is_integer(status),
    do: "Poskytovatel odmítl email (HTTP #{status})"

  defp delivery_error(:resend_api_key_not_configured), do: "Resend není nakonfigurován"
  defp delivery_error(_reason), do: "Dočasná chyba při odesílání"

  defp validate_subject(subject) do
    if valid_subject?(subject) do
      :ok
    else
      {:error, :invalid_subject}
    end
  end

  defp valid_subject?(subject),
    do: is_binary(subject) and String.trim(subject) != "" and String.length(subject) <= 255

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
