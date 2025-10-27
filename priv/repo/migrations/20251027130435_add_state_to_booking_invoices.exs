defmodule CozyCheckout.Repo.Migrations.AddStateToBookingInvoices do
  use Ecto.Migration

  def change do
    alter table(:booking_invoices) do
      add :state, :string, default: "draft", null: false
    end

    create index(:booking_invoices, [:state])
  end
end
