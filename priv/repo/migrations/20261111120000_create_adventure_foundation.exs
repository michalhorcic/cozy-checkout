defmodule CozyCheckout.Repo.Migrations.CreateAdventureFoundation do
  use Ecto.Migration

  def change do
    create table(:adventure_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :display_name, :string, null: false
      add :active, :boolean, null: false, default: true
      timestamps(type: :utc_datetime)
    end

    create unique_index(:adventure_profiles, [:slug])

    create table(:adventure_quests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :profile_id, references(:adventure_profiles, type: :binary_id), null: false
      add :code, :string, null: false
      add :version, :integer, null: false
      add :period_key, :string, null: false
      add :status, :string, null: false, default: "active"
      add :definition_snapshot, :map, null: false
      add :evidence, :map, null: false, default: %{}
      add :completed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:adventure_quests, [:profile_id, :code, :period_key])
    create index(:adventure_quests, [:profile_id, :status])
    create constraint(:adventure_quests, :adventure_quest_version, check: "version > 0")

    create constraint(:adventure_quests, :adventure_quest_state,
             check:
               "(status = 'active' AND completed_at IS NULL) OR (status = 'completed' AND completed_at IS NOT NULL)"
           )

    create table(:adventure_xp_transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :profile_id, references(:adventure_profiles, type: :binary_id), null: false
      add :quest_id, references(:adventure_quests, type: :binary_id), null: false
      add :reverses_id, references(:adventure_xp_transactions, type: :binary_id)
      add :award_key, :string, null: false
      add :amount, :integer, null: false
      add :reason, :text, null: false
      add :attribution, :string, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:adventure_xp_transactions, [:award_key])

    create unique_index(:adventure_xp_transactions, [:quest_id], where: "reverses_id IS NULL")

    create unique_index(:adventure_xp_transactions, [:reverses_id],
             where: "reverses_id IS NOT NULL"
           )

    create index(:adventure_xp_transactions, [:profile_id])

    create constraint(:adventure_xp_transactions, :adventure_xp_sign,
             check:
               "(reverses_id IS NULL AND amount > 0) OR (reverses_id IS NOT NULL AND amount < 0)"
           )

    create constraint(:adventure_xp_transactions, :adventure_xp_attribution,
             check: "attribution = 'self_selected'"
           )
  end
end
