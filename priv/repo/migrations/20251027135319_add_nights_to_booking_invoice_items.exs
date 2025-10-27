defmodule CozyCheckout.Repo.Migrations.AddNightsToBookingInvoiceItems do
  use Ecto.Migration

  def change do
    alter table(:booking_invoice_items) do
      add :nights, :integer, null: false, default: 1
    end
  end
end
