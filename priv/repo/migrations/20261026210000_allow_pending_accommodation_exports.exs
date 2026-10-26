defmodule CozyCheckout.Repo.Migrations.AllowPendingAccommodationExports do
  use Ecto.Migration

  def up do
    alter table(:accommodation_abra_exports) do
      modify :base_url, :text, null: true
      modify :company_id, :text, null: true
    end

    drop constraint(:accommodation_abra_exports, :valid_export_state)

    create constraint(:accommodation_abra_exports, :valid_export_state,
             check: "state IN ('queued', 'waiting', 'retrying', 'failed', 'synced')"
           )
  end

  def down do
    execute "UPDATE accommodation_abra_exports SET state = 'failed' WHERE state = 'waiting'"
    # An unprepared request has never contacted ABRA. Keep it visible on rollback.
    execute "UPDATE accommodation_abra_exports SET base_url = '' WHERE base_url IS NULL"
    execute "UPDATE accommodation_abra_exports SET company_id = '' WHERE company_id IS NULL"
    drop constraint(:accommodation_abra_exports, :valid_export_state)

    create constraint(:accommodation_abra_exports, :valid_export_state,
             check: "state IN ('queued', 'retrying', 'failed', 'synced')"
           )

    alter table(:accommodation_abra_exports) do
      modify :base_url, :text, null: false
      modify :company_id, :text, null: false
    end
  end
end
