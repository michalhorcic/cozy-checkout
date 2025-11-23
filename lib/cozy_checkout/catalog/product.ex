defmodule CozyCheckout.Catalog.Product do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [:name, :category_id, :active],
    sortable: [],
    default_limit: 20
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "products" do
    field :name, :string
    field :description, :string
    field :active, :boolean, default: true
    field :unit, :string
    field :default_unit_amounts, :string
    field :deleted_at, :utc_datetime

    belongs_to :category, CozyCheckout.Catalog.Category
    has_many :pricelists, CozyCheckout.Catalog.Pricelist
    has_many :order_items, CozyCheckout.Sales.OrderItem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, [:name, :description, :category_id, :active, :unit, :default_unit_amounts])
    |> validate_required([:name])
    |> validate_inclusion(:unit, ["ml", "L", "pcs", nil], message: "must be ml, L, pcs, or empty")
    |> validate_unit_amounts()
    |> foreign_key_constraint(:category_id)
  end

  defp validate_unit_amounts(changeset) do
    unit = get_field(changeset, :unit)
    default_amounts = get_change(changeset, :default_unit_amounts)

    cond do
      is_nil(unit) && is_nil(default_amounts) ->
        changeset

      is_nil(unit) && not is_nil(default_amounts) ->
        add_error(changeset, :default_unit_amounts, "can only be set when unit is specified")

      not is_nil(default_amounts) ->
        case Jason.decode(default_amounts) do
          {:ok, amounts} when is_list(amounts) ->
            if Enum.all?(amounts, &is_number/1) do
              changeset
            else
              add_error(changeset, :default_unit_amounts, "must be a JSON array of numbers")
            end

          _ ->
            add_error(changeset, :default_unit_amounts, "must be a valid JSON array")
        end

      true ->
        changeset
    end
  end
end
