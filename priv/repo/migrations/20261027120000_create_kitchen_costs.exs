defmodule CozyCheckout.Repo.Migrations.CreateKitchenCosts do
  use Ecto.Migration

  def change do
    create table(:kitchen_purchases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :import_id, :uuid
      add :merchant, :string, null: false
      add :purchased_on, :date, null: false
      add :document_number, :string
      add :currency, :string, null: false, default: "CZK"
      add :total_paid, :decimal, null: false
      add :rounding, :decimal, null: false, default: 0
      add :original_json, :map
      add :confirmed_at, :utc_datetime, null: false
      add :replaces_id, references(:kitchen_purchases, type: :binary_id, on_delete: :restrict)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:kitchen_purchases, [:import_id])
    create unique_index(:kitchen_purchases, [:replaces_id])
    create index(:kitchen_purchases, [:purchased_on])
    create index(:kitchen_purchases, [:merchant, :purchased_on, :document_number, :total_paid])
    create constraint(:kitchen_purchases, :kitchen_purchase_total, check: "total_paid >= 0")
    create constraint(:kitchen_purchases, :kitchen_purchase_currency, check: "currency = 'CZK'")

    create table(:kitchen_purchase_lines, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :purchase_id, references(:kitchen_purchases, type: :binary_id, on_delete: :restrict),
        null: false

      add :ingredient_id, references(:kitchen_ingredients, type: :binary_id, on_delete: :restrict)
      add :line_number, :integer, null: false
      add :source_name, :string, null: false
      add :classification, :string, null: false
      add :quantity, :decimal, null: false
      add :unit, :string, null: false
      add :package_count, :decimal
      add :package_quantity, :decimal
      add :package_unit, :string
      add :line_total, :decimal, null: false
      add :base_quantity, :decimal
      add :base_unit, :string
      add :ingredient_name, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:kitchen_purchase_lines, [:purchase_id, :line_number])
    create index(:kitchen_purchase_lines, [:ingredient_id])

    create constraint(:kitchen_purchase_lines, :kitchen_line_numbers,
             check: "line_number > 0 AND quantity > 0 AND line_total >= 0"
           )

    create constraint(:kitchen_purchase_lines, :kitchen_line_unit,
             check: "unit IN ('kg','g','l','ml','ks')"
           )

    create constraint(:kitchen_purchase_lines, :kitchen_line_mapping,
             check:
               "(classification = 'ingredient' AND ingredient_id IS NOT NULL AND base_quantity > 0 AND base_quantity IS NOT NULL AND base_unit IN ('kg','l','ks') AND base_unit IS NOT NULL AND ingredient_name IS NOT NULL) OR (classification IN ('unassigned','other') AND ingredient_id IS NULL AND base_quantity IS NULL AND base_unit IS NULL AND ingredient_name IS NULL)"
           )

    create constraint(:kitchen_purchase_lines, :kitchen_line_packaging,
             check:
               "(package_count IS NULL AND package_quantity IS NULL AND package_unit IS NULL) OR (package_count IS NOT NULL AND package_count > 0 AND package_quantity IS NOT NULL AND package_quantity > 0 AND package_unit IS NOT NULL AND package_unit IN ('kg','g','l','ml','ks'))"
           )

    create table(:kitchen_manual_prices, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :ingredient_id,
          references(:kitchen_ingredients, type: :binary_id, on_delete: :restrict), null: false

      add :valid_from, :date, null: false
      add :unit_price, :decimal, null: false
      add :base_unit, :string, null: false
      add :note, :text, null: false
      add :archived_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:kitchen_manual_prices, [:ingredient_id, :valid_from])

    create constraint(:kitchen_manual_prices, :kitchen_manual_price_positive,
             check: "unit_price > 0"
           )

    create constraint(:kitchen_manual_prices, :kitchen_manual_price_unit,
             check: "base_unit IN ('kg','l','ks')"
           )
  end
end
