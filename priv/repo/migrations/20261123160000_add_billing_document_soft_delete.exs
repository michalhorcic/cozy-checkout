defmodule CozyCheckout.Repo.Migrations.AddBillingDocumentSoftDelete do
  use Ecto.Migration

  def up do
    drop constraint(:accommodation_abra_exports, :valid_export_state)

    create constraint(:accommodation_abra_exports, :valid_export_state,
             check:
               "state IN ('queued', 'waiting', 'retrying', 'failed', 'synced', 'outdated', 'cancelled')"
           )

    alter table(:billing_documents) do
      add :deleted_at, :utc_datetime
    end

    drop index(:billing_documents, [:billing_account_id],
           name: :billing_one_final,
           where: "kind = 'final'"
         )

    create unique_index(:billing_documents, [:billing_account_id],
             name: :billing_one_final,
             where: "kind = 'final' AND deleted_at IS NULL"
           )
  end

  def down do
    execute "UPDATE accommodation_abra_exports SET state = 'synced' WHERE state = 'cancelled'"
    drop constraint(:accommodation_abra_exports, :valid_export_state)

    create constraint(:accommodation_abra_exports, :valid_export_state,
             check: "state IN ('queued', 'waiting', 'retrying', 'failed', 'synced', 'outdated')"
           )

    drop index(:billing_documents, [:billing_account_id], name: :billing_one_final)

    create unique_index(:billing_documents, [:billing_account_id],
             name: :billing_one_final,
             where: "kind = 'final'"
           )

    alter table(:billing_documents) do
      remove :deleted_at
    end
  end
end
