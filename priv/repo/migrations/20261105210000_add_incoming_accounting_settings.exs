defmodule CozyCheckout.Repo.Migrations.AddIncomingAccountingSettings do
  use Ecto.Migration

  def change do
    alter table(:incoming_documents) do
      add :accounting_settings, :map, null: false, default: %{}
    end
  end
end
