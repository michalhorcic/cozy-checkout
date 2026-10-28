defmodule CozyCheckout.KitchenCosts.Purchase do
  use Ecto.Schema
  import Ecto.Changeset
  alias CozyCheckout.KitchenCosts.PurchaseLine
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "kitchen_purchases" do
    field :import_id, Ecto.UUID
    field :merchant, :string
    field :purchased_on, :date
    field :document_number, :string
    field :currency, :string, default: "CZK"
    field :total_paid, :decimal
    field :rounding, :decimal, default: Decimal.new(0)
    field :original_json, :map
    field :confirmed_at, :utc_datetime
    belongs_to :replaces, __MODULE__
    has_many :lines, PurchaseLine, preload_order: [asc: :line_number]
    timestamps(type: :utc_datetime)
  end

  def changeset(purchase, attrs) do
    purchase
    |> cast(attrs, [
      :import_id,
      :merchant,
      :purchased_on,
      :document_number,
      :currency,
      :total_paid,
      :rounding,
      :original_json
    ])
    |> validate_required([:merchant, :purchased_on, :currency, :total_paid, :rounding])
    |> validate_length(:merchant, max: 255)
    |> validate_length(:document_number, max: 255)
    |> validate_inclusion(:currency, ["CZK"])
    |> validate_number(:total_paid, greater_than_or_equal_to: 0)
    |> cast_assoc(:lines, required: true)
    |> validate_totals()
    |> unique_constraint(:import_id)
    |> unique_constraint(:replaces_id)
    |> foreign_key_constraint(:replaces_id)
  end

  defp validate_totals(%{valid?: true} = cs) do
    lines = get_field(cs, :lines)
    numbers = Enum.map(lines, & &1.line_number)
    total = Enum.reduce(lines, get_field(cs, :rounding), &Decimal.add(&1.line_total, &2))

    cs =
      if length(numbers) == length(Enum.uniq(numbers)),
        do: cs,
        else: add_error(cs, :lines, "Čísla řádků musí být jedinečná")

    if Decimal.equal?(total, get_field(cs, :total_paid)),
      do: cs,
      else: add_error(cs, :total_paid, "Součet řádků a zaokrouhlení neodpovídá dokladu")
  end

  defp validate_totals(cs), do: cs
end
