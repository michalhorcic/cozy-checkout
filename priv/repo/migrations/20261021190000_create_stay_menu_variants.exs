defmodule CozyCheckout.Repo.Migrations.CreateStayMenuVariants do
  use Ecto.Migration

  def change do
    create table(:menu_variants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :days, :integer, null: false
      add :meal_plan, :string, null: false
      add :first_meal, :string, null: false
      add :last_meal, :string, null: false
      add :lock_version, :integer, null: false, default: 1
      add :deleted_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:menu_variants, [:name], where: "deleted_at IS NULL")
    create constraint(:menu_variants, :positive_days, check: "days > 0 AND days <= 366")

    create table(:menu_variant_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :menu_variant_id, references(:menu_variants, type: :binary_id, on_delete: :delete_all),
        null: false

      add :day_number, :integer, null: false
      add :meal_type, :string, null: false
      add :menu_text, :text, null: false
      add :supplements, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:menu_variant_items, [:menu_variant_id, :day_number, :meal_type])

    create table(:booking_menus, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :booking_id, references(:bookings, type: :binary_id, on_delete: :delete_all),
        null: false

      add :menu_variant_id, references(:menu_variants, type: :binary_id, on_delete: :restrict),
        null: false

      add :variant_name, :string, null: false
      add :source_revision, :integer, null: false
      add :booking_signature, :map, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:booking_menus, [:booking_id])

    create table(:booking_menu_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :booking_menu_id, references(:booking_menus, type: :binary_id, on_delete: :delete_all),
        null: false

      add :day_number, :integer, null: false
      add :date, :date, null: false
      add :meal_type, :string, null: false
      add :menu_text, :text, null: false
      add :supplements, :text
      add :manually_edited, :boolean, null: false, default: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:booking_menu_items, [:booking_menu_id, :date, :meal_type])
    create index(:booking_menu_items, [:date])
  end
end
