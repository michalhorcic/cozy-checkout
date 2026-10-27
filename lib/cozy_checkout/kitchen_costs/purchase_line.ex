defmodule CozyCheckout.KitchenCosts.PurchaseLine do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "kitchen_purchase_lines" do
    belongs_to :purchase, CozyCheckout.KitchenCosts.Purchase
    belongs_to :ingredient, CozyCheckout.Recipes.Ingredient
    field :line_number, :integer
    field :source_name, :string
    field :classification, :string, default: "unassigned"
    field :quantity, :decimal
    field :unit, :string
    field :package_count, :decimal
    field :package_quantity, :decimal
    field :package_unit, :string
    field :line_total, :decimal
    field :base_quantity, :decimal
    field :base_unit, :string
    field :ingredient_name, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(line, attrs) do
    line
    |> cast(attrs, [
      :ingredient_id,
      :line_number,
      :source_name,
      :classification,
      :quantity,
      :unit,
      :package_count,
      :package_quantity,
      :package_unit,
      :line_total
    ])
    |> validate_required([
      :line_number,
      :source_name,
      :classification,
      :quantity,
      :unit,
      :line_total
    ])
    |> validate_length(:source_name, max: 255)
    |> validate_number(:line_number, greater_than: 0)
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:line_total, greater_than_or_equal_to: 0)
    |> validate_number(:package_count, greater_than: 0)
    |> validate_number(:package_quantity, greater_than: 0)
    |> validate_inclusion(:unit, ["kg", "g", "l", "ml", "ks"])
    |> validate_inclusion(:package_unit, ["kg", "g", "l", "ml", "ks"])
    |> validate_inclusion(:classification, ["ingredient", "unassigned", "other"])
    |> validate_mapping()
    |> validate_packaging()
    |> foreign_key_constraint(:ingredient_id)
    |> unique_constraint([:purchase_id, :line_number])
  end

  defp validate_mapping(cs) do
    if get_field(cs, :classification) == "ingredient" do
      validate_required(cs, [:ingredient_id])
    else
      if get_field(cs, :ingredient_id),
        do: add_error(cs, :ingredient_id, "Položka není označena jako surovina"),
        else: cs
    end
  end

  defp validate_packaging(cs) do
    if Enum.any?([:package_count, :package_quantity, :package_unit], &get_field(cs, &1)) do
      cs = validate_required(cs, [:package_count, :package_quantity, :package_unit])

      if cs.valid? do
        amount = Decimal.mult(get_field(cs, :package_count), get_field(cs, :package_quantity))
        unit = get_field(cs, :package_unit)

        target =
          case get_field(cs, :unit) do
            "g" -> "kg"
            "ml" -> "l"
            other -> other
          end

        with {:ok, packed} <- CozyCheckout.Recipes.to_base(amount, unit, target),
             {:ok, total} <-
               CozyCheckout.Recipes.to_base(
                 get_field(cs, :quantity),
                 get_field(cs, :unit),
                 target
               ),
             true <- Decimal.equal?(packed, total) do
          cs
        else
          _ -> add_error(cs, :quantity, "Celkové množství neodpovídá balení")
        end
      else
        cs
      end
    else
      cs
    end
  end
end
