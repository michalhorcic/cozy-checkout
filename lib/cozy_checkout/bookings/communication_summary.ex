defmodule CozyCheckout.Bookings.CommunicationSummary do
  @moduledoc "Read-only email summaries for a page of bookings; acceptance is not delivery."
  import Ecto.Query
  alias CozyCheckout.Repo
  alias CozyCheckout.Billing.{Account, Document, Delivery, ManualDelivery}
  alias CozyCheckout.GuestEmails
  alias CozyCheckout.GuestEmails.TemplateCatalog

  def for_bookings([]), do: %{}

  def for_bookings(ids) do
    manual =
      from m in ManualDelivery,
        where: is_nil(m.voided_at),
        distinct: true,
        select: %{document_id: m.document_id}

    documents =
      from(d in Document,
        join: a in Account,
        on: a.id == d.billing_account_id,
        left_join: e in Delivery,
        on: e.document_id == d.id,
        left_join: m in subquery(manual),
        on: m.document_id == d.id,
        where: d.booking_id in ^ids and d.kind in ["advance", "final"] and is_nil(a.deleted_at),
        group_by: [d.booking_id, d.id],
        select: %{
          booking_id: d.booking_id,
          accepted: filter(count(e.id), e.state == "accepted") > 0 or count(m.document_id) > 0,
          pending: filter(count(e.id), e.state in ["queued", "retrying"]) > 0,
          failed: filter(count(e.id), e.state == "failed") > 0
        }
      )
      |> Repo.all()
      |> Enum.group_by(& &1.booking_id)

    template_ids = Enum.map(TemplateCatalog.list(), & &1.id)

    welcomes =
      from(e in GuestEmails.Delivery,
        where:
          e.booking_id in ^ids and e.content_mode == "template" and e.template_id in ^template_ids,
        group_by: e.booking_id,
        select: %{
          booking_id: e.booking_id,
          accepted: filter(count(e.id), e.state == "accepted") > 0,
          pending: filter(count(e.id), e.state in ["queued", "sending", "retrying"]) > 0,
          failed: filter(count(e.id), e.state == "failed") > 0
        }
      )
      |> Repo.all()
      |> Map.new(&{&1.booking_id, state(&1)})

    Map.new(ids, fn id ->
      rows = Map.get(documents, id, [])

      {id,
       %{
         invoice_count: length(rows),
         invoice_sent: Enum.count(rows, & &1.accepted),
         invoice_pending: Enum.count(rows, &(not &1.accepted and &1.pending)),
         invoice_failed: Enum.count(rows, &(not &1.accepted and not &1.pending and &1.failed)),
         welcome: Map.get(welcomes, id, :unsent)
       }}
    end)
  end

  defp state(%{accepted: true}), do: :sent
  defp state(%{pending: true}), do: :pending
  defp state(%{failed: true}), do: :failed
  defp state(_), do: :unsent
end
