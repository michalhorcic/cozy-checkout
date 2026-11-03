defmodule CozyCheckout.Abra.PdfTransfer do
  @moduledoc "Delivery state for PDF attachments, separate from accounting synchronization."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "abra_pdf_transfers" do
    belongs_to :export, CozyCheckout.Abra.AccommodationExport
    field :state, :string, default: "queued"
    field :error, :string
    field :sha256, :string
    field :uploaded_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
