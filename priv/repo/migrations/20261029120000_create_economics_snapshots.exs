defmodule CozyCheckout.Repo.Migrations.CreateEconomicsSnapshots do
  use Ecto.Migration

  def change do
    create table(:economics_sources, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :base_url, :text, null: false
      add :company_id, :text, null: false
      add :generation, :bigint, null: false, default: 0
      add :deleted_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:economics_sources, [:base_url, :company_id])

    create table(:economics_import_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source_id, references(:economics_sources, type: :binary_id), null: false
      add :period_code, :text, null: false
      add :generation, :bigint, null: false
      add :state, :text, null: false
      add :error, :text
      add :started_at, :utc_datetime, null: false
      add :completed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:economics_import_runs, [:source_id, :inserted_at])

    create constraint(:economics_import_runs, :economics_import_state,
             check: "state IN ('running', 'succeeded', 'failed')"
           )

    create table(:economics_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source_id, references(:economics_sources, type: :binary_id), null: false
      add :import_run_id, references(:economics_import_runs, type: :binary_id), null: false
      add :period_code, :text, null: false
      add :active, :boolean, default: true, null: false
      add :payload, :map, null: false
      add :fingerprint, :text, null: false
      add :started_at, :utc_datetime, null: false
      add :checked_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:economics_snapshots, [:source_id, :period_code],
             where: "active = true",
             name: :economics_active_snapshot_index
           )

    create index(:economics_snapshots, [:source_id, :period_code, :inserted_at])

    create table(:economics_confirmations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source_id, references(:economics_sources, type: :binary_id), null: false
      add :snapshot_id, references(:economics_snapshots, type: :binary_id), null: false
      add :month, :date, null: false
      add :fingerprint, :text, null: false
      add :evidence, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:economics_confirmations, [:source_id, :month, :fingerprint])
  end
end
