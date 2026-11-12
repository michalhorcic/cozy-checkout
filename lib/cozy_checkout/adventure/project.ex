defmodule CozyCheckout.Adventure.Project do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "adventure_projects" do
    field :title, :string
    field :purpose, :string, default: ""
    field :area, :string, default: "workshop"
    belongs_to :owner, CozyCheckout.Adventure.Profile
    field :due_on, :date
    field :budget, :decimal
    field :currency, :string, default: "CZK"
    field :price_basis, :string, default: "including_vat"
    field :reference, :string, default: ""
    field :status, :string, default: "idea"
    field :version, :integer, default: 1
    field :request_key, Ecto.UUID
    field :acceptance, :map, default: %{}
    field :archived_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def areas, do: ~w(reception rooms kitchen bar treasury workshop)
  def statuses, do: ~w(idea ready approved active accepted paused cancelled)

  def changeset(project, attrs) do
    project
    |> cast(attrs, [
      :title,
      :purpose,
      :area,
      :owner_id,
      :due_on,
      :budget,
      :currency,
      :price_basis,
      :reference
    ])
    |> update_change(:title, fn
      title when is_binary(title) -> String.trim(title)
      title -> title
    end)
    |> update_change(:purpose, &(&1 || ""))
    |> update_change(:reference, &(&1 || ""))
    |> validate_required([:title, :area, :currency, :price_basis])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_length(:purpose, max: 5000)
    |> validate_length(:reference, max: 1000)
    |> validate_inclusion(:area, areas())
    |> validate_format(:currency, ~r/^[A-Z]{3}$/)
    |> validate_inclusion(:price_basis, ~w(including_vat excluding_vat unknown))
    |> validate_number(:budget, greater_than_or_equal_to: 0, less_than: 1_000_000_000_000)
    |> validate_change(:budget, fn :budget, value ->
      if Decimal.equal?(value, Decimal.round(value, 2)),
        do: [],
        else: [budget: "must have at most two decimal places"]
    end)
    |> foreign_key_constraint(:owner_id)
  end
end
