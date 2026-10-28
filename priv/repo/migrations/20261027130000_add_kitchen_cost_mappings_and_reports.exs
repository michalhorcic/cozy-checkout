defmodule CozyCheckout.Repo.Migrations.AddKitchenCostMappingsAndReports do
  use Ecto.Migration

  def change do
    create table(:kitchen_purchase_mappings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :merchant_key, :text, null: false
      add :source_key, :text, null: false
      add :source_name, :string, null: false

      add :ingredient_id,
          references(:kitchen_ingredients, type: :binary_id, on_delete: :restrict), null: false

      add :lock_version, :integer, null: false, default: 1
      add :archived_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:kitchen_purchase_mappings, [:merchant_key, :source_key])

    create table(:kitchen_cost_reports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :start_date, :date, null: false
      add :end_date, :date, null: false
      add :booking_id, references(:bookings, type: :binary_id, on_delete: :restrict)
      add :snapshot, :map, null: false
      add :calculated_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create constraint(:kitchen_cost_reports, :kitchen_report_range,
             check: "end_date >= start_date AND end_date - start_date <= 365"
           )

    create index(:kitchen_cost_reports, [:start_date, :end_date])
  end
end
