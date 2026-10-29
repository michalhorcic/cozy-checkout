defmodule CozyCheckout.Economics.Snapshot do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "economics_snapshots" do
    belongs_to :source, CozyCheckout.Economics.Source
    belongs_to :import_run, CozyCheckout.Economics.ImportRun
    field :period_code, :string
    field :active, :boolean, default: true
    field :payload, :map
    field :fingerprint, :string
    field :started_at, :utc_datetime
    field :checked_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
