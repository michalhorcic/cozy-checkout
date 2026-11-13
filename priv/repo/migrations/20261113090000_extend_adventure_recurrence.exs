defmodule CozyCheckout.Repo.Migrations.ExtendAdventureRecurrence do
  use Ecto.Migration

  def up, do: replace_rules(~w(daily weekly monthly semiannual yearly once))

  # PostgreSQL refuses the downgrade while any template still uses a new cadence.
  # The transactional DDL preserves the existing constraint and all records on failure.
  def down, do: replace_rules(~w(daily weekly once))

  defp replace_rules(cadences) do
    cadence_values = Enum.map_join(cadences, ",", &"'#{&1}'")
    drop constraint(:adventure_task_templates, :adventure_template_rules)

    create constraint(:adventure_task_templates, :adventure_template_rules,
             check:
               "version > 0 AND xp BETWEEN 1 AND 10000 AND size IN ('small','medium','large') AND cadence IN (#{cadence_values}) AND status IN ('active','paused','archived') AND priority IN ('low','normal','high') AND scope IN ('personal','shared') AND (scope != 'shared' OR assigned_profile_id IS NULL) AND cardinality(weekdays) BETWEEN 1 AND 7 AND weekdays <@ ARRAY[1,2,3,4,5,6,7] AND applicability IN ('always','campaign','guests') AND ((applicability = 'campaign' AND campaign_id IS NOT NULL) OR (applicability != 'campaign' AND campaign_id IS NULL))"
           )
  end
end
