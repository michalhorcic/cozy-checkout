defmodule CozyCheckout.Catalog.Product do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "products" do
    field :name, :string
    field :description, :string
    field :active, :boolean, default: true
    field :deleted_at, :utc_datetime

    belongs_to :category, CozyCheckout.Catalog.Category
    has_many :pricelists, CozyCheckout.Catalog.Pricelist
    has_many :order_items, CozyCheckout.Sales.OrderItem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, [:name, :description, :category_id, :active])
    |> validate_required([:name])
    |> foreign_key_constraint(:category_id)
  end
end
