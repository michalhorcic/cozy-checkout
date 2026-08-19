defmodule CozyCheckout.Repo.Migrations.AddAbraSyncToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :abra_sync_status, :string
      add :abra_sync_attempts, :integer, default: 0, null: false
      add :abra_document_id, :string
      add :abra_synced_at, :utc_datetime
      add :abra_sync_error, :text
    end

    create index(:orders, [:abra_sync_status])
  end
end
