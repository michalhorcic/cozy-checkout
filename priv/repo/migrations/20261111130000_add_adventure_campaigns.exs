defmodule CozyCheckout.Repo.Migrations.AddAdventureCampaigns do
  use Ecto.Migration

  def change do
    create table(:adventure_campaigns, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :starts_on, :date, null: false
      add :ends_on, :date, null: false
      add :capacity, :integer, null: false
      add :completed_goal, :integer, null: false
      add :reserved_goal, :integer, null: false
      add :occupancy_goal, :integer, null: false
      add :status, :string, null: false, default: "draft"
      add :rules_version, :string, null: false, default: "stays_v1"
      add :timezone, :string, null: false, default: "Europe/Prague"
      add :activated_at, :utc_datetime
      add :closed_at, :utc_datetime
      add :activated_by_id, references(:adventure_profiles, type: :binary_id)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:adventure_campaigns, [:status], where: "status = 'active'")

    create constraint(:adventure_campaigns, :adventure_campaign_dates,
             check: "ends_on >= starts_on AND ends_on - starts_on <= 1095"
           )

    create constraint(:adventure_campaigns, :adventure_campaign_goals,
             check:
               "capacity BETWEEN 1 AND 500 AND completed_goal BETWEEN 1 AND 100000 AND reserved_goal BETWEEN 1 AND 1000000 AND occupancy_goal BETWEEN 1 AND 100"
           )

    create constraint(:adventure_campaigns, :adventure_campaign_state,
             check:
               "(status = 'draft' AND activated_at IS NULL AND activated_by_id IS NULL AND closed_at IS NULL) OR (status = 'active' AND activated_at IS NOT NULL AND activated_by_id IS NOT NULL AND closed_at IS NULL) OR (status = 'closed' AND activated_at IS NOT NULL AND activated_by_id IS NOT NULL AND closed_at IS NOT NULL)"
           )

    create constraint(:adventure_campaigns, :adventure_campaign_rules,
             check: "timezone = 'Europe/Prague' AND rules_version = 'stays_v1'"
           )

    create table(:adventure_unlocks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :campaign_id, references(:adventure_campaigns, type: :binary_id), null: false
      add :code, :string, null: false
      add :rules_version, :string, null: false
      add :xp, :integer, null: false
      add :status, :string, null: false, default: "unlocked"
      add :unlocked_at, :utc_datetime, null: false
      add :revoked_at, :utc_datetime
      add :evidence, :map, null: false
      add :revocation_evidence, :map
      timestamps(type: :utc_datetime)
    end

    create unique_index(:adventure_unlocks, [:campaign_id, :code])

    create constraint(:adventure_unlocks, :adventure_unlock_state,
             check:
               "xp > 0 AND ((status = 'unlocked' AND revoked_at IS NULL) OR (status = 'revoked' AND revoked_at IS NOT NULL AND revocation_evidence IS NOT NULL))"
           )

    create table(:adventure_evaluations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :campaign_id, references(:adventure_campaigns, type: :binary_id), null: false
      add :actor_id, references(:adventure_profiles, type: :binary_id), null: false
      add :snapshot, :map, null: false
      add :as_of, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:adventure_evaluations, [:campaign_id, :as_of])

    alter table(:adventure_campaigns) do
      add :last_evaluation_id, references(:adventure_evaluations, type: :binary_id)
    end

    alter table(:adventure_xp_transactions) do
      modify :profile_id, :binary_id, null: true, from: {:binary_id, null: false}
      modify :quest_id, :binary_id, null: true, from: {:binary_id, null: false}
      add :unlock_id, references(:adventure_unlocks, type: :binary_id)
      add :recipient_type, :string, null: false, default: "profile"
    end

    execute(
      "ALTER TABLE adventure_xp_transactions DROP CONSTRAINT adventure_xp_attribution",
      "ALTER TABLE adventure_xp_transactions ADD CONSTRAINT adventure_xp_attribution CHECK (attribution = 'self_selected')"
    )

    create constraint(:adventure_xp_transactions, :adventure_xp_recipient,
             check:
               "(recipient_type = 'profile' AND profile_id IS NOT NULL AND quest_id IS NOT NULL AND unlock_id IS NULL AND attribution = 'self_selected') OR (recipient_type = 'shared' AND profile_id IS NULL AND quest_id IS NULL AND unlock_id IS NOT NULL AND attribution = 'automatic')"
           )

    create unique_index(:adventure_xp_transactions, [:unlock_id], where: "reverses_id IS NULL")
  end
end
