defmodule CozyCheckout.Repo.Migrations.CreateEconomicsCostMapping do
  use Ecto.Migration

  def change do
    create table(:economics_cost_mapping_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source_id, references(:economics_sources, type: :binary_id), null: false
      add :number, :integer, null: false
      add :state, :text, null: false, default: "draft"
      add :note, :text, null: false
      add :published_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:economics_cost_mapping_versions, [:source_id, :number])

    create unique_index(:economics_cost_mapping_versions, [:source_id],
             where: "state = 'active'",
             name: :economics_active_cost_mapping
           )

    create constraint(:economics_cost_mapping_versions, :cost_version_state,
             check:
               "state IN ('draft', 'active', 'superseded') AND number > 0 AND (state = 'draft' OR published_at IS NOT NULL)"
           )

    for table <- [:economics_cost_rules, :economics_cost_overrides] do
      create table(table, primary_key: false) do
        add :id, :binary_id, primary_key: true

        add :version_id, references(:economics_cost_mapping_versions, type: :binary_id),
          null: false

        add :account, :text, null: false
        add :behavior, :text, null: false
        add :extraordinary, :boolean, null: false, default: false
        add :fixed_percent, :decimal, precision: 10, scale: 6
        add :reason, :text, null: false
        add :deleted_at, :utc_datetime

        if table == :economics_cost_rules do
          add :partner_id, :text
          add :description_contains, :text
          add :valid_from, :date, null: false
          add :valid_to, :date
        else
          add :module, :text, null: false
          add :document_id, :text, null: false
          add :month, :date, null: false
          add :fingerprint, :text, null: false
        end

        timestamps(type: :utc_datetime)
      end

      create index(table, [:version_id])

      create constraint(table, :"#{table}_behavior",
               check:
                 "behavior IN ('fixed', 'variable', 'mixed', 'unclassified') AND (fixed_percent IS NULL OR (behavior = 'mixed' AND fixed_percent >= 0 AND fixed_percent <= 100)) AND length(trim(reason)) > 0"
             )
    end

    create constraint(:economics_cost_rules, :cost_rule_months,
             check:
               "EXTRACT(DAY FROM valid_from) = 1 AND (valid_to IS NULL OR (EXTRACT(DAY FROM valid_to) = 1 AND valid_to >= valid_from))"
           )

    create constraint(:economics_cost_overrides, :cost_override_month,
             check: "EXTRACT(DAY FROM month) = 1"
           )

    create unique_index(
             :economics_cost_overrides,
             [:version_id, :module, :document_id, :account, :month],
             where: "deleted_at IS NULL",
             name: :economics_cost_override_target
           )

    # Published interpretations remain reproducible, including direct SQL callers.
    execute """
            CREATE FUNCTION economics_guard_cost_item() RETURNS trigger AS $$
            DECLARE version_state text;
            BEGIN
              IF TG_OP <> 'INSERT' THEN
                SELECT state INTO version_state FROM economics_cost_mapping_versions WHERE id = OLD.version_id FOR SHARE;
                IF version_state <> 'draft' THEN RAISE EXCEPTION 'Published cost mapping is immutable'; END IF;
              END IF;
              IF TG_OP <> 'DELETE' THEN
                SELECT state INTO version_state FROM economics_cost_mapping_versions WHERE id = NEW.version_id FOR SHARE;
                IF version_state <> 'draft' THEN RAISE EXCEPTION 'Published cost mapping is immutable'; END IF;
                RETURN NEW;
              END IF;
              RETURN OLD;
            END;
            $$ LANGUAGE plpgsql;
            """,
            "DROP FUNCTION economics_guard_cost_item()"

    for table <- [:economics_cost_rules, :economics_cost_overrides] do
      execute "CREATE TRIGGER guard_cost_item BEFORE INSERT OR UPDATE OR DELETE ON #{table} FOR EACH ROW EXECUTE FUNCTION economics_guard_cost_item()",
              "DROP TRIGGER guard_cost_item ON #{table}"
    end

    execute """
            CREATE FUNCTION economics_guard_cost_version() RETURNS trigger AS $$
            BEGIN
              IF OLD.state <> 'draft' THEN
                IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Published cost mapping is immutable'; END IF;
                IF NOT (OLD.state = 'active' AND NEW.state = 'superseded'
                  AND (to_jsonb(NEW) - 'state' - 'updated_at') = (to_jsonb(OLD) - 'state' - 'updated_at')) THEN
                  RAISE EXCEPTION 'Published cost mapping is immutable';
                END IF;
              END IF;
              IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
              RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;
            """,
            "DROP FUNCTION economics_guard_cost_version()"

    execute "CREATE TRIGGER guard_cost_version BEFORE UPDATE OR DELETE ON economics_cost_mapping_versions FOR EACH ROW EXECUTE FUNCTION economics_guard_cost_version()",
            "DROP TRIGGER guard_cost_version ON economics_cost_mapping_versions"
  end
end
