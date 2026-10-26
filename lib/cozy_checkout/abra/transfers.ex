defmodule CozyCheckout.Abra.Transfers do
  @moduledoc "Read model and recovery entry point for accommodation document and bank transfers."
  import Ecto.Query
  alias CozyCheckout.Repo
  alias CozyCheckout.Abra.{Accommodation, AccommodationExport, BankConfirmation, BankPayments}
  alias CozyCheckout.Billing.{Document, Payment}

  def label("queued"), do: "Čeká na přenos"
  def label("waiting"), do: "Čeká na podmínky"
  def label("retrying"), do: "Opakuje se přenos"
  def label("failed"), do: "Chyba přenosu"
  def label("conflict"), do: "Vyžaduje účetní kontrolu"
  def label("synced"), do: "Přeneseno"

  def for_documents(documents) do
    ids = Enum.map(documents, & &1.id)

    if ids == [] do
      %{}
    else
      exports = exports() |> where([e, d], d.id in ^ids) |> Repo.all()
      payments = payments() |> where([c, p, d], d.id in ^ids) |> Repo.all()
      Enum.group_by(exports ++ payments, & &1.document_id)
    end
  end

  def list(mode \\ "problems", page \\ 1) do
    export_query = filter(exports(), mode)
    payment_query = filter(payments(), mode)
    combined = union_all(export_query, ^payment_query)

    Repo.all(
      from row in subquery(combined),
        order_by: [desc: row.updated_at, asc: row.category, asc: row.id],
        limit: 50,
        offset: ^((page - 1) * 50)
    )
  end

  def retry("document", id) do
    export = Repo.get!(AccommodationExport, id)
    Accommodation.enqueue(export.document_id)
  end

  def retry("payment", id), do: BankPayments.retry(id)
  def retry(_, _), do: {:error, "Neznámý druh přenosu"}

  def configuration_notice do
    cfg = Accommodation.config()

    cond do
      not Accommodation.enabled?() ->
        "Integrace ubytování s ABRA je vypnutá; přenosy čekají."

      not match?(%DateTime{}, cfg[:enabled_from]) ->
        "Chybí okamžik zapojení pobytů; automatický export se nezařazuje."

      Enum.any?(
        ~w(base_url company_id username password advance_type_code bank_account_code)a,
        &(cfg[&1] in [nil, ""])
      ) ->
        "Konfigurace ABRA není úplná; doplňte připojení a mapování výzev."

      true ->
        nil
    end
  end

  defp filter(query, "all"), do: query
  defp filter(query, "pending"), do: where(query, [row], row.state in ["queued", "waiting"])
  defp filter(query, _), do: where(query, [row], row.state in ["failed", "retrying", "conflict"])

  defp exports do
    from e in AccommodationExport,
      join: d in Document,
      on: d.id == e.document_id,
      select: %{
        id: e.id,
        category: "document",
        document_id: d.id,
        booking_id: d.booking_id,
        number: d.number,
        state: e.state,
        error: e.error,
        updated_at: e.updated_at
      }
  end

  defp payments do
    from c in BankConfirmation,
      join: p in Payment,
      on: p.id == c.payment_id,
      join: d in Document,
      on: d.id == coalesce(p.tax_document_id, p.document_id),
      select: %{
        id: c.id,
        category: "payment",
        document_id: d.id,
        booking_id: d.booking_id,
        number: d.number,
        state: c.state,
        error: c.error,
        updated_at: c.updated_at
      }
  end
end
