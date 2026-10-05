defmodule CozyCheckout.Workers.BookingEmailWorker do
  @moduledoc """
  Delivers one guest email and retries transient provider failures.
  """

  use Oban.Worker, queue: :booking_emails, max_attempts: 5

  import Swoosh.Email

  alias CozyCheckout.GuestEmails
  alias CozyCheckout.GuestEmails.TemplateCatalog
  alias CozyCheckout.Mailer

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, id: job_id}) do
    with true <- GuestEmails.configured?(),
         {:ok, content} <- content_for_delivery(args),
         {:ok, _response} <-
           deliver(
             job_id,
             args["recipient_email"],
             args["subject"],
             content.html,
             content.text
           ) do
      :ok
    else
      false ->
        Logger.error("Booking email #{job_id} was not sent: RESEND_API_KEY is not configured")
        {:discard, :resend_api_key_not_configured}

      {:error, {:template_read_failed, template_id, reason}} ->
        Logger.error(
          "Booking email #{job_id} could not load template #{template_id}: #{inspect(reason)}"
        )

        {:discard, {:template_read_failed, template_id}}

      {:error, :empty_body} ->
        Logger.error("Booking email #{job_id} has an empty custom message")
        {:discard, :empty_body}

      {:error, {status, _provider_error} = reason} when status in 400..499 and status != 429 ->
        Logger.error("Resend rejected booking email #{job_id} with HTTP #{status}")
        {:discard, reason}

      {:error, reason} ->
        Logger.warning("Booking email #{job_id} failed and will be retried: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp content_for_delivery(%{"html_body" => html, "text_body" => text}) do
    {:ok, %{html: html, text: text}}
  end

  defp content_for_delivery(%{"template_id" => template_id}) do
    TemplateCatalog.render(template_id)
  end

  defp content_for_delivery(%{"content_mode" => "custom", "custom_body" => body}) do
    TemplateCatalog.render_custom(body)
  end

  defp content_for_delivery(_args), do: {:error, :missing_email_content}

  defp deliver(job_id, recipient_email, subject, html, text) do
    email =
      new()
      |> from(Application.fetch_env!(:cozy_checkout, :email_from_address))
      |> to(recipient_email)
      |> subject(subject)
      |> html_body(html)
      |> maybe_text_body(text)
      |> put_provider_option(:idempotency_key, "booking-email-#{job_id}")

    Mailer.deliver(email)
  end

  defp maybe_text_body(email, text) when is_binary(text), do: text_body(email, text)
  defp maybe_text_body(email, _text), do: email
end
