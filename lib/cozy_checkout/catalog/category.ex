defmodule CozyCheckout.Catalog.Category do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "categories" do
    field :name, :string
    field :description, :string
    field :order, :integer, default: 0
    field :deleted_at, :utc_datetime

    has_many :products, CozyCheckout.Catalog.Product

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :description, :order])
    |> validate_required([:name])
    |> validate_number(:order, greater_than_or_equal_to: 0)
    |> unique_constraint(:name)
  end
end
