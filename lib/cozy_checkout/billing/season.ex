defmodule CozyCheckout.Billing.Season do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "billing_seasons" do
    field :name, :string
    field :valid_from, :date
    field :valid_to, :date
    field :adult, :decimal
    field :infant, :decimal
    field :child, :decimal
    field :vat_rate, :decimal, default: Decimal.new(12)
    field :deleted_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:name, :valid_from, :valid_to, :adult, :infant, :child, :vat_rate])
    |> validate_required([:name, :valid_from, :valid_to, :adult, :infant, :child, :vat_rate])
    |> validate_number(:adult, greater_than_or_equal_to: 0)
    |> validate_number(:infant, greater_than_or_equal_to: 0)
    |> validate_number(:child, greater_than_or_equal_to: 0)
    |> validate_inclusion(:vat_rate, Enum.map([0, 12, 21], &Decimal.new/1))
    |> check_constraint(:valid_to, name: :valid_dates)
    |> exclusion_constraint(:valid_from,
      name: :billing_seasons_no_overlap,
      message: "Období se překrývá s jinou sezonou"
    )
  end
end
