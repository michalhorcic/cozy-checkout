defmodule CozyCheckout.Repo.Migrations.AddAdventureDutyQuests do
  use Ecto.Migration

  def up do
    alter table(:adventure_quests) do
      add :source_namespace, :string
      add :source_ref, :uuid
      add :source_type, :string
      add :source_context, :map
      add :source_request_key, :uuid
      add :source_previous_id, references(:adventure_quests, type: :binary_id)
      add :source_attempt, :integer
    end

    create unique_index(:adventure_quests, [:source_namespace, :source_ref, :source_type],
             name: :adventure_duty_open_work,
             where:
               "source_namespace IS NOT NULL AND status IN ('waiting', 'active') AND archived_at IS NULL"
           )

    create unique_index(:adventure_quests, [:source_request_key])

    create unique_index(
             :adventure_quests,
             [:source_namespace, :source_ref, :source_type, :source_attempt],
             name: :adventure_duty_attempt
           )

    create constraint(:adventure_quests, :adventure_duty_source,
             check: """
             (source_namespace IS NULL AND source_ref IS NULL AND source_type IS NULL
              AND source_context IS NULL AND source_request_key IS NULL
              AND source_previous_id IS NULL AND source_attempt IS NULL)
             OR
             (source_namespace IS NOT NULL AND source_namespace = 'operation_v1'
              AND source_ref IS NOT NULL AND source_type IS NOT NULL
              AND source_type IN ('details', 'menu') AND source_context IS NOT NULL
              AND source_request_key IS NOT NULL AND source_attempt IS NOT NULL
              AND source_attempt > 0 AND managed AND template_id IS NULL
              AND ((source_attempt = 1 AND source_previous_id IS NULL)
                   OR (source_attempt > 1 AND source_previous_id IS NOT NULL)))
             """
           )

    execute """
    CREATE FUNCTION adventure_preserve_duty_source() RETURNS trigger AS $$
    BEGIN
      IF ROW(NEW.source_namespace, NEW.source_ref, NEW.source_type, NEW.source_context,
             NEW.source_request_key, NEW.source_previous_id, NEW.source_attempt)
         IS DISTINCT FROM
         ROW(OLD.source_namespace, OLD.source_ref, OLD.source_type, OLD.source_context,
             OLD.source_request_key, OLD.source_previous_id, OLD.source_attempt) THEN
        RAISE EXCEPTION 'Adventure duty source history is immutable';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER adventure_preserve_duty_source
    BEFORE UPDATE ON adventure_quests
    FOR EACH ROW EXECUTE FUNCTION adventure_preserve_duty_source();
    """
  end

  def down do
    raise "Adventure duty quest history must be retained; restore a database backup to roll back"
  end
end
