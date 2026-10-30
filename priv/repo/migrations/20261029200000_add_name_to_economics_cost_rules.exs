defmodule CozyCheckout.Repo.Migrations.AddNameToEconomicsCostRules do
  use Ecto.Migration

  def change do
    alter table(:economics_cost_rules) do
      add :partner_name, :text
    end

    create constraint(:economics_cost_rules, :cost_rule_partner_identity,
             check:
               "partner_name IS NULL OR (partner_id IS NULL AND length(trim(partner_name)) > 0)"
           )
  end
end
