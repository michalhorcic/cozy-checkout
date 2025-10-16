defmodule CozyCheckout.Repo.Migrations.AddInvoiceNumberToPayments do
  use Ecto.Migration

  def change do
    alter table(:payments) do
      add :invoice_number, :string
    end

    create unique_index(:payments, [:invoice_number])
  end
end
