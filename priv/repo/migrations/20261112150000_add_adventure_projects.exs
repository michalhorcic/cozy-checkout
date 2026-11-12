defmodule CozyCheckout.Repo.Migrations.AddAdventureProjects do
  use Ecto.Migration

  def up do
    create table(:adventure_projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :purpose, :text, null: false, default: ""
      add :area, :string, null: false, default: "workshop"
      add :owner_id, references(:adventure_profiles, type: :binary_id)
      add :due_on, :date
      add :budget, :decimal, precision: 16, scale: 2
      add :currency, :string, null: false, default: "CZK"
      add :price_basis, :string, null: false, default: "including_vat"
      add :reference, :text, null: false, default: ""
      add :status, :string, null: false, default: "idea"
      add :version, :integer, null: false, default: 1
      add :request_key, :uuid, null: false
      add :acceptance, :map, null: false, default: %{}
      add :archived_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:adventure_projects, [:request_key])
    create index(:adventure_projects, [:inserted_at, :id])

    create constraint(:adventure_projects, :adventure_project_rules,
             check:
               "version > 0 AND status IN ('idea','ready','approved','active','accepted','paused','cancelled') AND area IN ('reception','rooms','kitchen','bar','treasury','workshop') AND (budget IS NULL OR budget >= 0) AND currency ~ '^[A-Z]{3}$' AND price_basis IN ('including_vat','excluding_vat','unknown') AND (status != 'accepted' OR acceptance ? 'confirmed_at')"
           )

    create table(:adventure_project_stages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:adventure_projects, type: :binary_id), null: false
      add :quest_id, references(:adventure_quests, type: :binary_id), null: false
      add :position, :integer, null: false
      add :output, :text, null: false
      add :quest_snapshot, :map, null: false
      add :archived_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:adventure_project_stages, [:project_id, :position])
    create unique_index(:adventure_project_stages, [:project_id, :quest_id])
    create constraint(:adventure_project_stages, :adventure_stage_position, check: "position > 0")

    create table(:adventure_project_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:adventure_projects, type: :binary_id), null: false
      add :actor_id, references(:adventure_profiles, type: :binary_id), null: false
      add :version, :integer, null: false
      add :action, :string, null: false
      add :snapshot, :map, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:adventure_project_events, [:project_id, :version])

    execute """
    CREATE FUNCTION adventure_project_event_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN RAISE EXCEPTION 'Adventure project history is immutable'; END;
    $$
    """

    execute """
    CREATE TRIGGER adventure_project_event_immutable BEFORE UPDATE OR DELETE ON adventure_project_events
    FOR EACH ROW EXECUTE FUNCTION adventure_project_event_immutable()
    """
  end

  def down do
    raise "Project acceptance and audit history must be retained; assess rollback compatibility first"
  end
end
