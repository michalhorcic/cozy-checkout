defmodule CozyCheckout.Repo.Migrations.CreateInvoiceCounters do
  use Ecto.Migration

  def change do
    create table(:invoice_counters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :year, :integer, null: false
      add :counter, :integer, null: false, default: 0

      timestamps()
    end

    create unique_index(:invoice_counters, [:year])
  end
end
