defmodule CozyCheckout.Meals.MenuVariant do
  use Ecto.Schema
  import Ecto.Changeset
  alias CozyCheckout.Meals.SlotSchedule

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "menu_variants" do
    field :name, :string
    field :days, :integer, default: 3
    field :meal_plan, :string, default: "full_board"
    field :first_meal, :string, default: "dinner"
    field :last_meal, :string, default: "breakfast"
    field :lock_version, :integer, default: 1
    field :deleted_at, :utc_datetime
    has_many :items, CozyCheckout.Meals.MenuVariantItem, on_replace: :delete
    timestamps(type: :utc_datetime)
  end

  def settings_changeset(variant, attrs) do
    variant
    |> cast(attrs, [:name, :days, :meal_plan, :first_meal, :last_meal])
    |> validate_required([:name, :days, :meal_plan, :first_meal, :last_meal])
    |> update_change(:name, &String.trim/1)
    |> validate_length(:name, max: 200)
    |> validate_number(:days, greater_than: 0, less_than_or_equal_to: 366)
    |> validate_inclusion(:meal_plan, ["half_board", "full_board"])
    |> validate_inclusion(:first_meal, ["breakfast", "lunch", "dinner"])
    |> validate_inclusion(:last_meal, ["breakfast", "lunch", "dinner"])
    |> validate_boundaries()
    |> unique_constraint(:name, name: :menu_variants_name_index)
  end

  def changeset(variant, attrs) do
    variant
    |> settings_changeset(attrs)
    |> cast_assoc(:items, with: &CozyCheckout.Meals.MenuVariantItem.changeset/2)
    |> validate_slots()
  end

  def slots(variant),
    do: SlotSchedule.slots(variant.days, variant.meal_plan, variant.first_meal, variant.last_meal)

  defp validate_boundaries(cs) do
    cs =
      if get_field(cs, :meal_plan) == "half_board" do
        Enum.reduce([:first_meal, :last_meal], cs, fn field, acc ->
          if get_field(acc, field) == "lunch",
            do: add_error(acc, field, "Polopenze nezahrnuje oběd"),
            else: acc
        end)
      else
        cs
      end

    first = get_field(cs, :first_meal)
    last = get_field(cs, :last_meal)

    if get_field(cs, :days) == 1 and first in ["breakfast", "lunch", "dinner"] and
         last in ["breakfast", "lunch", "dinner"] and
         SlotSchedule.rank(first) > SlotSchedule.rank(last) do
      add_error(cs, :last_meal, "Poslední jídlo musí následovat po prvním nebo být stejné")
    else
      cs
    end
  end

  defp validate_slots(cs) do
    expected = slots(apply_changes(cs)) |> MapSet.new()
    items = get_field(cs, :items, [])
    actual = Enum.map(items, &{&1.day_number, &1.meal_type})

    if MapSet.new(actual) == expected and length(actual) == MapSet.size(expected) and actual != [] do
      cs
    else
      add_error(
        cs,
        :items,
        "Rozpis musí obsahovat právě jedno hlavní jídlo nebo bufet pro každé podání. Aktualizujte rozpis."
      )
    end
  end
end
