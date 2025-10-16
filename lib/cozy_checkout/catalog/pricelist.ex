defmodule CozyCheckout.Catalog.Pricelist do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "pricelists" do
    field :price, :decimal
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
    |> cast(attrs, [:product_id, :price, :vat_rate, :valid_from, :valid_to, :active])
    |> validate_required([:product_id, :price, :vat_rate, :valid_from])
    |> validate_number(:price, greater_than: 0)
    |> validate_number(:vat_rate, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:product_id)
    |> validate_date_range()
  end

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
