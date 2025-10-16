defmodule CozyCheckout.Guests.Guest do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "guests" do
    field :name, :string
    field :room_number, :string
    field :phone, :string
    field :notes, :string
    field :check_in_date, :date
    field :check_out_date, :date
    field :deleted_at, :utc_datetime

    has_many :orders, CozyCheckout.Sales.Order

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(guest, attrs) do
    guest
    |> cast(attrs, [:name, :room_number, :phone, :notes, :check_in_date, :check_out_date])
    |> validate_required([:name])
    |> validate_date_range()
  end

  defp validate_date_range(changeset) do
    check_in = get_field(changeset, :check_in_date)
    check_out = get_field(changeset, :check_out_date)

    if check_in && check_out && Date.compare(check_in, check_out) == :gt do
      add_error(changeset, :check_out_date, "must be after check-in date")
    else
      changeset
    end
  end
end
