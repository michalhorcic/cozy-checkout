defmodule CozyCheckout.Economics.Confirmation do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "economics_confirmations" do
    belongs_to :source, CozyCheckout.Economics.Source
    belongs_to :snapshot, CozyCheckout.Economics.Snapshot
    field :month, :date
    field :fingerprint, :string
    field :evidence, :string
    timestamps(type: :utc_datetime)
  end
end
