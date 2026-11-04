defmodule CozyCheckout.Repo.Migrations.AllowOutdatedAdvanceExports do
  use Ecto.Migration

  def up do
    drop constraint(:accommodation_abra_exports, :valid_export_state)

    create constraint(:accommodation_abra_exports, :valid_export_state,
             check: "state IN ('queued', 'waiting', 'retrying', 'failed', 'synced', 'outdated')"
           )
  end

  def down do
    execute "UPDATE accommodation_abra_exports SET state = 'failed' WHERE state = 'outdated'"
    drop constraint(:accommodation_abra_exports, :valid_export_state)

    create constraint(:accommodation_abra_exports, :valid_export_state,
             check: "state IN ('queued', 'waiting', 'retrying', 'failed', 'synced')"
           )
  end
end
