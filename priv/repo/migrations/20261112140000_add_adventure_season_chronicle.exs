defmodule CozyCheckout.Repo.Migrations.AddAdventureSeasonChronicle do
  use Ecto.Migration

  def change do
    execute(
      "ALTER TABLE adventure_campaigns DROP CONSTRAINT adventure_campaign_goals",
      "ALTER TABLE adventure_campaigns ADD CONSTRAINT adventure_campaign_goals CHECK (capacity BETWEEN 1 AND 500 AND completed_goal BETWEEN 1 AND 100000 AND reserved_goal BETWEEN 1 AND 1000000 AND occupancy_goal BETWEEN 1 AND 100)"
    )

    execute(
      "ALTER TABLE adventure_campaigns DROP CONSTRAINT adventure_campaign_rules",
      "ALTER TABLE adventure_campaigns ADD CONSTRAINT adventure_campaign_rules CHECK (timezone = 'Europe/Prague' AND rules_version = 'stays_v1')"
    )

    execute(
      "ALTER TABLE adventure_campaigns DROP CONSTRAINT adventure_campaign_state",
      "ALTER TABLE adventure_campaigns ADD CONSTRAINT adventure_campaign_state CHECK ((status = 'draft' AND activated_at IS NULL AND activated_by_id IS NULL AND closed_at IS NULL) OR (status = 'active' AND activated_at IS NOT NULL AND activated_by_id IS NOT NULL AND closed_at IS NULL) OR (status = 'closed' AND activated_at IS NOT NULL AND activated_by_id IS NOT NULL AND closed_at IS NOT NULL))"
    )

    alter table(:adventure_campaigns) do
      modify :capacity, :integer, null: true, from: {:integer, null: false}
      modify :completed_goal, :integer, null: true, from: {:integer, null: false}
      modify :reserved_goal, :integer, null: true, from: {:integer, null: false}
      modify :occupancy_goal, :integer, null: true, from: {:integer, null: false}
      add :historical, :boolean, null: false, default: false
    end

    create constraint(:adventure_campaigns, :adventure_campaign_goals,
             check: """
             (capacity IS NULL OR capacity BETWEEN 1 AND 500) AND
             (completed_goal IS NULL OR completed_goal BETWEEN 1 AND 100000) AND
             (reserved_goal IS NULL OR reserved_goal BETWEEN 1 AND 1000000) AND
             (occupancy_goal IS NULL OR occupancy_goal BETWEEN 1 AND 100) AND
             (rules_version = 'season_v1' OR
               (capacity IS NOT NULL AND completed_goal IS NOT NULL AND
                reserved_goal IS NOT NULL AND occupancy_goal IS NOT NULL))
             """
           )

    create constraint(:adventure_campaigns, :adventure_campaign_rules,
             check: "timezone = 'Europe/Prague' AND rules_version IN ('stays_v1', 'season_v1')"
           )

    create constraint(:adventure_campaigns, :adventure_campaign_state,
             check: """
             (historical = false AND (
               (status = 'draft' AND activated_at IS NULL AND activated_by_id IS NULL AND closed_at IS NULL) OR
               (status = 'active' AND activated_at IS NOT NULL AND activated_by_id IS NOT NULL AND closed_at IS NULL) OR
               (status = 'closed' AND activated_at IS NOT NULL AND activated_by_id IS NOT NULL AND closed_at IS NOT NULL)
             )) OR
             (historical = true AND rules_version = 'season_v1' AND status = 'closed' AND
              activated_at IS NULL AND activated_by_id IS NULL AND closed_at IS NOT NULL)
             """
           )

    alter table(:adventure_evaluations) do
      add :version, :integer
      add :previous_evaluation_id, references(:adventure_evaluations, type: :binary_id)
      add :correction_reason, :text
      add :campaign_metadata, :map
    end

    create unique_index(:adventure_evaluations, [:campaign_id, :version],
             where: "version IS NOT NULL"
           )

    create constraint(:adventure_evaluations, :adventure_evaluation_version,
             check: """
             (version IS NULL AND previous_evaluation_id IS NULL AND campaign_metadata IS NULL AND correction_reason IS NULL) OR
             (version IS NOT NULL AND version > 0 AND campaign_metadata IS NOT NULL AND
               ((version = 1 AND previous_evaluation_id IS NULL) OR
                (version > 1 AND previous_evaluation_id IS NOT NULL)))
             """
           )

    create constraint(:adventure_evaluations, :adventure_evaluation_reason,
             check:
               "correction_reason IS NULL OR (correction_reason ~ '[^[:space:]]' AND char_length(correction_reason) <= 1000)"
           )

    execute(
      """
      CREATE FUNCTION adventure_protect_campaign_period() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF OLD.status <> 'draft' AND
          (NEW.starts_on IS DISTINCT FROM OLD.starts_on OR NEW.ends_on IS DISTINCT FROM OLD.ends_on OR
            NEW.capacity IS DISTINCT FROM OLD.capacity OR NEW.rules_version IS DISTINCT FROM OLD.rules_version OR
            NEW.completed_goal IS DISTINCT FROM OLD.completed_goal OR NEW.reserved_goal IS DISTINCT FROM OLD.reserved_goal OR
            NEW.occupancy_goal IS DISTINCT FROM OLD.occupancy_goal OR NEW.timezone IS DISTINCT FROM OLD.timezone OR
            NEW.name IS DISTINCT FROM OLD.name OR
            NEW.historical IS DISTINCT FROM OLD.historical) THEN
          RAISE EXCEPTION 'Activated campaign period, capacity and rules are immutable'
            USING ERRCODE = 'check_violation', CONSTRAINT = 'adventure_campaign_immutable_period';
        END IF;
        RETURN NEW;
      END; $$
      """,
      "DROP FUNCTION adventure_protect_campaign_period() CASCADE"
    )

    execute(
      "CREATE TRIGGER adventure_campaign_immutable_period BEFORE UPDATE ON adventure_campaigns FOR EACH ROW EXECUTE FUNCTION adventure_protect_campaign_period()",
      "DROP TRIGGER adventure_campaign_immutable_period ON adventure_campaigns"
    )

    execute(
      """
      CREATE FUNCTION adventure_protect_chronicle() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE
        campaign_rules text;
        previous adventure_evaluations%ROWTYPE;
      BEGIN
        IF TG_OP <> 'INSERT' THEN
          IF OLD.version IS NOT NULL THEN
            RAISE EXCEPTION 'Chronicle evaluations are append-only'
              USING ERRCODE = 'check_violation', CONSTRAINT = 'adventure_evaluation_immutable';
          END IF;
          IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
          RETURN NEW;
        END IF;

        SELECT rules_version INTO campaign_rules FROM adventure_campaigns WHERE id = NEW.campaign_id;
        IF campaign_rules = 'season_v1' AND (NEW.version IS NULL OR NEW.campaign_metadata IS NULL) THEN
          RAISE EXCEPTION 'Season evaluations require numbered metadata snapshots'
            USING ERRCODE = 'check_violation', CONSTRAINT = 'adventure_evaluation_version';
        END IF;
        IF NEW.previous_evaluation_id IS NOT NULL THEN
          SELECT * INTO previous FROM adventure_evaluations WHERE id = NEW.previous_evaluation_id;
          IF previous.campaign_id IS DISTINCT FROM NEW.campaign_id OR
             previous.version IS DISTINCT FROM NEW.version - 1 THEN
            RAISE EXCEPTION 'Previous evaluation must be the preceding version of the same season'
              USING ERRCODE = 'check_violation', CONSTRAINT = 'adventure_evaluation_previous';
          END IF;
          IF previous.campaign_metadata->>'status' = 'closed' AND
             (NEW.correction_reason IS NULL OR NEW.correction_reason !~ '[^[:space:]]') THEN
            RAISE EXCEPTION 'Closed chronicle corrections require a reason'
              USING ERRCODE = 'check_violation', CONSTRAINT = 'adventure_evaluation_reason';
          END IF;
        END IF;
        RETURN NEW;
      END; $$
      """,
      "DROP FUNCTION adventure_protect_chronicle() CASCADE"
    )

    execute(
      "CREATE TRIGGER adventure_evaluation_immutable BEFORE INSERT OR UPDATE OR DELETE ON adventure_evaluations FOR EACH ROW EXECUTE FUNCTION adventure_protect_chronicle()",
      "DROP TRIGGER adventure_evaluation_immutable ON adventure_evaluations"
    )
  end
end
