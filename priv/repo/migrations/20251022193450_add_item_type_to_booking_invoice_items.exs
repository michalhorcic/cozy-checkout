defmodule CozyCheckout.Repo.Migrations.AddItemTypeToBookingInvoiceItems do
  use Ecto.Migration

  def change do
    alter table(:booking_invoice_items) do
      add :item_type, :string, default: "person", null: false
    end

    create index(:booking_invoice_items, [:item_type])
  end
end
