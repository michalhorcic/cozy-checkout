defmodule CozyCheckout.Catalog.Pricelist do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [:active, :product_id],
    sortable: [],
    default_limit: 20
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "pricelists" do
    field :price, :decimal
    field :price_tiers, {:array, :map}, default: []
    field :vat_rate, :decimal
    field :valid_from, :date
    field :valid_to, :date
    field :active, :boolean, default: true
    field :deleted_at, :utc_datetime

    belongs_to :product, CozyCheckout.Catalog.Product

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(pricelist, attrs) do
    pricelist
    |> cast(attrs, [:product_id, :price, :price_tiers, :vat_rate, :valid_from, :valid_to, :active])
    |> validate_required([:product_id, :vat_rate, :valid_from])
    |> validate_price_or_price_tiers()
    |> validate_number(:vat_rate, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:product_id)
    |> validate_date_range()
  end

  defp validate_price_or_price_tiers(changeset) do
    price = get_field(changeset, :price)
    price_tiers = get_field(changeset, :price_tiers)

    cond do
      # Has price_tiers - validate them
      price_tiers != nil && price_tiers != [] ->
        validate_price_tiers(changeset)

      # Has single price - validate it (backwards compatibility)
      price != nil ->
        validate_number(changeset, :price, greater_than: 0)

      # Neither set - error
      true ->
        add_error(changeset, :price, "either price or price_tiers must be set")
    end
  end

  defp validate_price_tiers(changeset) do
    case get_field(changeset, :price_tiers) do
      nil ->
        changeset

      [] ->
        changeset

      tiers when is_list(tiers) ->
        if Enum.all?(tiers, &valid_price_tier?/1) do
          changeset
        else
          add_error(
            changeset,
            :price_tiers,
            "contains invalid price tiers (must have unit_amount > 0 and price >= 0)"
          )
        end

      _ ->
        add_error(changeset, :price_tiers, "must be a list")
    end
  end

  defp valid_price_tier?(%{"unit_amount" => amount, "price" => price})
       when is_number(amount) and amount > 0 and is_number(price) and price >= 0,
       do: true

  defp valid_price_tier?(%{unit_amount: amount, price: price})
       when is_number(amount) and amount > 0 and is_number(price) and price >= 0,
       do: true

  defp valid_price_tier?(_), do: false

  @doc """
  Get price for a specific unit amount from price tiers.
  Returns {:ok, price} if found, {:error, :no_price_for_amount} otherwise.
  Falls back to single price if price_tiers is empty.
  """
  def get_price_for_amount(%__MODULE__{price_tiers: []}, _unit_amount) do
    {:error, :no_price_for_amount}
  end

  def get_price_for_amount(%__MODULE__{price_tiers: nil}, _unit_amount) do
    {:error, :no_price_for_amount}
  end

  def get_price_for_amount(%__MODULE__{price_tiers: tiers}, unit_amount)
      when is_list(tiers) do
    # Convert to Decimal for accurate comparison
    unit_amount_decimal = Decimal.new(to_string(unit_amount))

    tier =
      Enum.find(tiers, fn tier ->
        tier_amount = get_tier_amount(tier)
        Decimal.equal?(tier_amount, unit_amount_decimal)
      end)

    case tier do
      %{"price" => price} -> {:ok, Decimal.new(to_string(price))}
      %{price: price} -> {:ok, Decimal.new(to_string(price))}
      nil -> {:error, :no_price_for_amount}
    end
  end

  def get_price_for_amount(_, _), do: {:error, :no_price_for_amount}

  defp get_tier_amount(%{"unit_amount" => amount}), do: Decimal.new(to_string(amount))
  defp get_tier_amount(%{unit_amount: amount}), do: Decimal.new(to_string(amount))

  defp validate_date_range(changeset) do
    valid_from = get_field(changeset, :valid_from)
    valid_to = get_field(changeset, :valid_to)

    if valid_from && valid_to && Date.compare(valid_from, valid_to) == :gt do
      add_error(changeset, :valid_to, "must be after valid_from")
    else
      changeset
    end
  end
end
