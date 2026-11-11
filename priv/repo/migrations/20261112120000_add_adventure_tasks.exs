defmodule CozyCheckout.Repo.Migrations.AddAdventureTasks do
  use Ecto.Migration

  def up do
    alter table(:adventure_quests) do
      modify :profile_id, :binary_id, null: true
      add :managed, :boolean, null: false, default: false
      add :scope, :string, null: false, default: "personal"
      add :assigned_profile_id, references(:adventure_profiles, type: :binary_id)
      add :created_by_id, references(:adventure_profiles, type: :binary_id)
      add :due_on, :date
      add :priority, :string, null: false, default: "normal"
      add :category, :string, null: false, default: "Provoz"
      add :description, :text, null: false, default: ""
      add :archived_at, :utc_datetime
    end

    drop constraint(:adventure_quests, :adventure_quest_state)

    create constraint(:adventure_quests, :adventure_quest_state,
             check:
               "(status IN ('waiting', 'active', 'cancelled') AND completed_at IS NULL) OR (status = 'completed' AND completed_at IS NOT NULL)"
           )

    create constraint(:adventure_quests, :adventure_task_scope,
             check:
               "scope IN ('personal', 'shared') AND (scope != 'shared' OR assigned_profile_id IS NULL) AND ((managed AND profile_id IS NULL AND created_by_id IS NOT NULL) OR (NOT managed AND profile_id IS NOT NULL)) AND (NOT managed OR scope = 'shared' OR status != 'active' OR assigned_profile_id IS NOT NULL)"
           )

    create constraint(:adventure_quests, :adventure_task_priority,
             check: "priority IN ('low', 'normal', 'high')"
           )

    create index(:adventure_quests, [:assigned_profile_id, :status])
    create index(:adventure_quests, [:managed, :status, :due_on])

    drop constraint(:adventure_xp_transactions, :adventure_xp_recipient)

    create constraint(:adventure_xp_transactions, :adventure_xp_recipient,
             check:
               "(recipient_type = 'profile' AND profile_id IS NOT NULL AND quest_id IS NOT NULL AND unlock_id IS NULL AND attribution = 'self_selected') OR (recipient_type = 'shared' AND profile_id IS NULL AND ((quest_id IS NULL AND unlock_id IS NOT NULL AND attribution = 'automatic') OR (quest_id IS NOT NULL AND unlock_id IS NULL AND attribution = 'self_selected')))"
           )
  end

  def down do
    raise "Adventure task history must be retained; restore a database backup to roll back"
  end
end
