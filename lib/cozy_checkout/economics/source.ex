defmodule CozyCheckout.Economics.Source do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "economics_sources" do
    field :base_url, :string
    field :company_id, :string
    field :generation, :integer, default: 0
    field :deleted_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
