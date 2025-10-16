defmodule CozyCheckout.Repo.Migrations.CreatePayments do
  use Ecto.Migration

  def change do
    create table(:payments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, references(:orders, type: :binary_id, on_delete: :restrict), null: false
      add :amount, :decimal, precision: 10, scale: 2, null: false
      add :payment_method, :string, null: false
      add :payment_date, :date, null: false
      add :notes, :text
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:payments, [:order_id])
    create index(:payments, [:payment_method])
    create index(:payments, [:payment_date])
    create index(:payments, [:deleted_at])
  end
end
