defmodule CozyCheckout.Meals do
  @moduledoc """
  The Meals context - manages meal planning for the cottage.
  """

  import Ecto.Query, warn: false
  alias CozyCheckout.Repo

  alias CozyCheckout.Meals.Meal
  alias CozyCheckout.Meals.MealTemplate
  alias CozyCheckout.Bookings.Booking

  @doc """
  Returns meals for a specific week (Sunday to Saturday).
  Returns a map with date as key and list of meals for that date.
  """
  def get_meals_for_week(start_date) do
    end_date = Date.add(start_date, 6)

    Meal
    |> where([m], is_nil(m.deleted_at))
    |> where([m], m.date >= ^start_date and m.date <= ^end_date)
    |> order_by([m], [m.date, m.meal_type])
    |> Repo.all()
    |> Enum.group_by(& &1.date)
  end

  @doc """
  Returns meals for a specific date range.
  """
  def get_meals_for_date_range(start_date, end_date) do
    Meal
    |> where([m], is_nil(m.deleted_at))
    |> where([m], m.date >= ^start_date and m.date <= ^end_date)
    |> order_by([m], [m.date, m.meal_type])
    |> Repo.all()
  end

  @doc """
  Gets a single meal by date and type.
  """
  def get_meal_by_date_and_type(date, meal_type) do
    Meal
    |> where([m], is_nil(m.deleted_at))
    |> where([m], m.date == ^date and m.meal_type == ^meal_type)
    |> Repo.one()
  end

  @doc """
  Creates or updates a meal (upsert based on date + meal_type).
  """
  def upsert_meal(date, meal_type, attrs) do
    case get_meal_by_date_and_type(date, meal_type) do
      nil ->
        create_meal(Map.merge(attrs, %{date: date, meal_type: meal_type}))

      meal ->
        update_meal(meal, attrs)
    end
  end

  @doc """
  Creates a meal.
  """
  def create_meal(attrs \\ %{}) do
    %Meal{}
    |> Meal.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a meal.
  """
  def update_meal(%Meal{} = meal, attrs) do
    meal
    |> Meal.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a meal (soft delete).
  """
  def delete_meal(%Meal{} = meal) do
    meal
    |> Ecto.Changeset.change(deleted_at: DateTime.truncate(DateTime.utc_now(), :second))
    |> Repo.update()
  end

  @doc """
  Copies a meal to multiple dates.
  """
  def copy_meal_to_dates(%Meal{} = meal, target_dates) when is_list(target_dates) do
    results =
      Enum.map(target_dates, fn date ->
        attrs = %{
          menu_text: meal.menu_text,
          dietary_notes: meal.dietary_notes
        }

        upsert_meal(date, meal.meal_type, attrs)
      end)

    # Return {:ok, count} if all succeeded, {:error, failed} if any failed
    case Enum.split_with(results, fn {status, _} -> status == :ok end) do
      {successes, []} -> {:ok, length(successes)}
      {_, failures} -> {:error, failures}
    end
  end

  # Meal Templates

  @doc """
  Returns the list of meal templates.
  """
  def list_meal_templates do
    MealTemplate
    |> where([mt], is_nil(mt.deleted_at))
    |> order_by([mt], [mt.category, mt.name])
    |> Repo.all()
  end

  @doc """
  Returns meal templates for a specific category.
  """
  def list_meal_templates_by_category(category) do
    MealTemplate
    |> where([mt], is_nil(mt.deleted_at))
    |> where([mt], mt.category == ^category)
    |> order_by([mt], mt.name)
    |> Repo.all()
  end

  @doc """
  Gets a single meal template.
  """
  def get_meal_template!(id) do
    MealTemplate
    |> where([mt], is_nil(mt.deleted_at))
    |> Repo.get!(id)
  end

  @doc """
  Creates a meal template.
  """
  def create_meal_template(attrs \\ %{}) do
    %MealTemplate{}
    |> MealTemplate.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a meal template.
  """
  def update_meal_template(%MealTemplate{} = meal_template, attrs) do
    meal_template
    |> MealTemplate.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a meal template (soft delete).
  """
  def delete_meal_template(%MealTemplate{} = meal_template) do
    meal_template
    |> Ecto.Changeset.change(deleted_at: DateTime.truncate(DateTime.utc_now(), :second))
    |> Repo.update()
  end

  # Dietary Restrictions

  @doc """
  Gets dietary restrictions for active bookings in a date range.
  Returns a list of maps with booking info and dietary restrictions.
  """
  def get_dietary_restrictions_for_week(start_date) do
    end_date = Date.add(start_date, 6)

    Booking
    |> join(:inner, [b], g in assoc(b, :guest))
    |> where([b], is_nil(b.deleted_at))
    |> where([b], b.status in ["upcoming", "active"])
    |> where([b], b.check_in_date <= ^end_date)
    |> where([b], is_nil(b.check_out_date) or b.check_out_date > ^start_date)
    |> where([b], not is_nil(b.dietary_restrictions) and b.dietary_restrictions != "")
    |> select([b, g], %{
      booking_id: b.id,
      guest_name: g.name,
      dietary_restrictions: b.dietary_restrictions,
      check_in_date: b.check_in_date,
      check_out_date: b.check_out_date,
      room_number: b.room_number
    })
    |> Repo.all()
  end

  @doc """
  Gets all dietary restrictions for currently active bookings.
  """
  def get_current_dietary_restrictions do
    today = Date.utc_today()

    Booking
    |> join(:inner, [b], g in assoc(b, :guest))
    |> where([b], is_nil(b.deleted_at))
    |> where([b], b.status in ["upcoming", "active"])
    |> where([b], b.check_in_date <= ^today)
    |> where([b], is_nil(b.check_out_date) or b.check_out_date > ^today)
    |> where([b], not is_nil(b.dietary_restrictions) and b.dietary_restrictions != "")
    |> select([b, g], %{
      booking_id: b.id,
      guest_name: g.name,
      dietary_restrictions: b.dietary_restrictions,
      check_in_date: b.check_in_date,
      check_out_date: b.check_out_date,
      room_number: b.room_number
    })
    |> Repo.all()
  end

  @doc """
  Returns the start of week (Sunday) for a given date.
  """
  def start_of_week(date) do
    day_of_week = Date.day_of_week(date, :sunday)
    Date.add(date, -(day_of_week - 1))
  end

  @doc """
  Returns true if a meal has been planned for the given date and meal type.
  """
  def meal_planned?(date, meal_type) do
    case get_meal_by_date_and_type(date, meal_type) do
      nil -> false
      meal -> meal.menu_text not in [nil, ""]
    end
  end

  @doc """
  Checks if a high-capacity day needs meal planning.
  Returns :warning if guest_count > 20 and meal not planned.
  """
  def check_meal_planning_status(date, meal_type, guest_count) do
    cond do
      guest_count > 20 and not meal_planned?(date, meal_type) -> :warning
      true -> :ok
    end
  end
end
