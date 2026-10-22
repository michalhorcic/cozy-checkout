defmodule CozyCheckout.Billing.Profile do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "billing_profiles" do
    field :singleton, :boolean, default: true
    field :data, :map, default: %{}
    timestamps(type: :utc_datetime)
  end
end
