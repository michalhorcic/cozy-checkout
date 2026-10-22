defmodule CozyCheckout.Workers.BillingEmailWorker do
  use Oban.Worker, queue: :billing, max_attempts: 5
  import Ecto.Query
  import Swoosh.Email, except: [from: 2]
  alias CozyCheckout.{Billing, Repo, Mailer}
  alias CozyCheckout.Billing.Delivery

  def perform(%Oban.Job{args: %{"delivery_id" => id}, attempt: attempt, max_attempts: max}) do
    delivery = Repo.get!(Delivery, id)

    with {:ok, document} <- Billing.ensure_pdf(delivery.document_id) do
      result =
        Repo.transaction(fn ->
          row = Repo.one!(from d in Delivery, where: d.id == ^id, lock: "FOR UPDATE")

          if row.state == "accepted" do
            :ok
          else
            email =
              new()
              |> Swoosh.Email.from(Application.fetch_env!(:cozy_checkout, :email_from_address))
              |> reply_to(Application.fetch_env!(:cozy_checkout, :email_from_address))
              |> to(row.recipient)
              |> subject(row.subject)
              |> text_body(row.body)
              |> attachment(
                Swoosh.Attachment.new({:data, document.pdf},
                  filename: "#{document.number}.pdf",
                  content_type: "application/pdf"
                )
              )
              |> put_provider_option(:idempotency_key, "billing-#{row.id}")

            case Mailer.deliver(email) do
              {:ok, _} ->
                row
                |> Ecto.Changeset.change(
                  state: "accepted",
                  attempts: attempt,
                  error: nil,
                  accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
                )
                |> Repo.update!()

                :ok

              {:error, reason} ->
                row
                |> Ecto.Changeset.change(
                  state: if(attempt >= max, do: "failed", else: "retrying"),
                  attempts: attempt,
                  error: inspect(reason)
                )
                |> Repo.update!()

                {:error, inspect(reason)}
            end
          end
        end)

      case result do
        {:ok, value} -> value
        {:error, reason} -> {:error, inspect(reason)}
      end
    else
      {:error, reason} ->
        delivery
        |> Ecto.Changeset.change(
          state: if(attempt >= max, do: "failed", else: "retrying"),
          attempts: attempt,
          error: inspect(reason)
        )
        |> Repo.update!()

        {:error, inspect(reason)}
    end
  end
end
