defmodule CozyCheckout.Repo.Migrations.AddMealDetailsToBookings do
  use Ecto.Migration

  def change do
    alter table(:bookings) do
      # NULL deliberately means not yet specified, including existing/iCal bookings.
      add :meal_plan, :string
      add :meal_adults, :integer
      add :meal_children, :integer
      add :first_meal, :string
      add :last_meal, :string
    end

    create constraint(:bookings, :meal_adults_nonnegative, check: "meal_adults >= 0")
    create constraint(:bookings, :meal_children_nonnegative, check: "meal_children >= 0")
  end
end
