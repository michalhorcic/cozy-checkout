defmodule CozyCheckout.Economics.ImportRun do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "economics_import_runs" do
    belongs_to :source, CozyCheckout.Economics.Source
    field :period_code, :string
    field :generation, :integer
    field :state, :string
    field :error, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
