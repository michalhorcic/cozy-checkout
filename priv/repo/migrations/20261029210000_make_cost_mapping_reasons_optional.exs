defmodule CozyCheckout.Repo.Migrations.MakeCostMappingReasonsOptional do
  use Ecto.Migration

  @assignment_check "behavior IN ('fixed', 'variable', 'mixed', 'unclassified') AND (fixed_percent IS NULL OR (behavior = 'mixed' AND fixed_percent >= 0 AND fixed_percent <= 100))"

  def up do
    for table <- [:economics_cost_rules, :economics_cost_overrides] do
      drop constraint(table, :"#{table}_behavior")

      alter table(table) do
        modify :reason, :text, null: true
      end

      create constraint(table, :"#{table}_behavior",
               check:
                 @assignment_check <>
                   " AND (fixed_percent IS NULL OR (reason IS NOT NULL AND length(trim(reason)) > 0))"
             )
    end
  end

  def down do
    for table <- [:economics_cost_rules, :economics_cost_overrides] do
      drop constraint(table, :"#{table}_behavior")

      alter table(table) do
        modify :reason, :text, null: false
      end

      create constraint(table, :"#{table}_behavior",
               check: @assignment_check <> " AND length(trim(reason)) > 0"
             )
    end
  end
end
