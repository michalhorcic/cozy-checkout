defmodule CozyCheckout.Repo.Migrations.AddAdventureTaskTemplates do
  use Ecto.Migration

  def up do
    create table(:adventure_task_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :description, :text, null: false, default: ""
      add :category, :string, null: false, default: "Provoz"
      add :priority, :string, null: false, default: "normal"
      add :scope, :string, null: false, default: "personal"
      add :assigned_profile_id, references(:adventure_profiles, type: :binary_id)
      add :size, :string, null: false, default: "small"
      add :xp, :integer, null: false, default: 50
      add :cadence, :string, null: false, default: "daily"
      add :weekdays, {:array, :integer}, null: false, default: [1]
      add :starts_on, :date, null: false
      add :next_due_on, :date
      add :applicability, :string, null: false, default: "always"
      add :campaign_id, references(:adventure_campaigns, type: :binary_id)
      add :status, :string, null: false, default: "paused"
      add :version, :integer, null: false, default: 1
      add :seed_key, :string
      add :legacy_profile_id, references(:adventure_profiles, type: :binary_id)
      add :legacy_code, :string
      add :last_check, :map, null: false, default: %{}
      add :created_by_id, references(:adventure_profiles, type: :binary_id)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:adventure_task_templates, [:seed_key])
    create index(:adventure_task_templates, [:status, :next_due_on])

    create constraint(:adventure_task_templates, :adventure_template_rules,
             check:
               "version > 0 AND xp BETWEEN 1 AND 10000 AND size IN ('small','medium','large') AND cadence IN ('daily','weekly','once') AND status IN ('active','paused','archived') AND priority IN ('low','normal','high') AND scope IN ('personal','shared') AND (scope != 'shared' OR assigned_profile_id IS NULL) AND cardinality(weekdays) BETWEEN 1 AND 7 AND weekdays <@ ARRAY[1,2,3,4,5,6,7] AND applicability IN ('always','campaign','guests') AND ((applicability = 'campaign' AND campaign_id IS NOT NULL) OR (applicability != 'campaign' AND campaign_id IS NULL))"
           )

    create table(:adventure_template_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :template_id, references(:adventure_task_templates, type: :binary_id), null: false
      add :version, :integer, null: false
      add :definition, :map, null: false
      add :actor_id, references(:adventure_profiles, type: :binary_id)
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:adventure_template_versions, [:template_id, :version])

    alter table(:adventure_quests) do
      add :template_id, references(:adventure_task_templates, type: :binary_id)
      add :first_due_on, :date
      add :schedule_history, :map, null: false, default: %{}
    end

    create unique_index(:adventure_quests, [:template_id],
             name: :adventure_one_open_occurrence,
             where:
               "template_id IS NOT NULL AND status IN ('waiting','active') AND archived_at IS NULL"
           )

    create unique_index(:adventure_quests, [:template_id, :period_key])

    # Start paused: migrating definitions must not silently generate obligations.
    # Original quests, UUIDs, snapshots and award keys are not rewritten.
    execute """
    INSERT INTO adventure_task_templates
      (id, title, xp, size, cadence, category, scope, assigned_profile_id, legacy_profile_id, starts_on, next_due_on,
       seed_key, legacy_code, inserted_at, updated_at)
    SELECT gen_random_uuid(), d.title, d.xp, CASE d.xp WHEN 100 THEN 'medium' WHEN 250 THEN 'large' ELSE 'small' END, d.cadence, 'Provoz', 'personal', p.id, p.id,
      timezone('Europe/Prague', now())::date, timezone('Europe/Prague', now())::date,
      'legacy:' || p.id::text || ':' || d.code, d.code, timezone('UTC', now()), timezone('UTC', now())
    FROM adventure_profiles p CROSS JOIN (VALUES
      ('prepare_stay', 'Připravit další pobyt', 50, 'weekly'),
      ('review_deposits', 'Zkontrolovat otevřené zálohy', 50, 'weekly'),
      ('shopping_plan', 'Dokončit týdenní nákupní plán', 100, 'weekly'),
      ('improvement', 'Zavést jedno provozní zlepšení', 250, 'once')
    ) AS d(code, title, xp, cadence)
    """

    execute """
    INSERT INTO adventure_template_versions (id, template_id, version, definition, inserted_at)
    SELECT gen_random_uuid(), t.id, 1, (to_jsonb(t) - 'last_check') || jsonb_build_object('timezone', 'Europe/Prague', 'rules_version', 'recurrence_v1'), timezone('UTC', now())
    FROM adventure_task_templates t
    """
  end

  def down do
    raise "Recurring task history must be retained; assess rollback compatibility before removing it"
  end
end
