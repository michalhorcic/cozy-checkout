defmodule CozyCheckout.Repo.Migrations.CreateBookingInvoices do
  use Ecto.Migration

  def change do
    # Booking Invoice Header
    create table(:booking_invoices, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :booking_id, references(:bookings, on_delete: :delete_all, type: :binary_id), null: false

      # Calculated totals (cached from line items)
      add :subtotal, :decimal, precision: 10, scale: 2
      add :vat_amount, :decimal, precision: 10, scale: 2
      add :total_price, :decimal, precision: 10, scale: 2

      # Invoice metadata
      add :invoice_number, :string
      add :invoice_generated_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:booking_invoices, [:booking_id])
    create unique_index(:booking_invoices, [:invoice_number])

    # Booking Invoice Line Items
    create table(:booking_invoice_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :booking_invoice_id, references(:booking_invoices, on_delete: :delete_all, type: :binary_id), null: false

      # Line item details
      add :name, :string, null: false
      add :quantity, :integer, null: false
      add :price_per_night, :decimal, precision: 10, scale: 2, null: false
      add :vat_rate, :decimal, precision: 5, scale: 2, null: false

      # Calculated totals (cached)
      add :subtotal, :decimal, precision: 10, scale: 2
      add :vat_amount, :decimal, precision: 10, scale: 2
      add :total, :decimal, precision: 10, scale: 2

      # For ordering
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:booking_invoice_items, [:booking_invoice_id])
    create index(:booking_invoice_items, [:position])
  end
end
