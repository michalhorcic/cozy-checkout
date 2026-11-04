defmodule CozyCheckout.Billing.Account do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "billing_accounts" do
    has_one :calculation, CozyCheckout.Bookings.BookingInvoice, foreign_key: :billing_account_id
    belongs_to :booking, CozyCheckout.Bookings.Booking
    field :name, :string
    field :default, :boolean, default: false
    field :adults, :integer, default: 0
    field :infants, :integer, default: 0
    field :children, :integer, default: 0
    field :check_in_date, :date
    field :check_out_date, :date
    field :deleted_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:name, :adults, :infants, :children, :check_in_date, :check_out_date])
    |> validate_required([:name, :adults, :infants, :children])
    |> validate_length(:name, max: 200)
    |> validate_number(:adults, greater_than_or_equal_to: 0)
    |> validate_number(:infants, greater_than_or_equal_to: 0)
    |> validate_number(:children, greater_than_or_equal_to: 0)
    |> validate_dates()
  end

  defp validate_dates(cs) do
    first = get_field(cs, :check_in_date)
    last = get_field(cs, :check_out_date)

    if first && last && Date.compare(first, last) != :lt,
      do: add_error(cs, :check_out_date, "Odjezd musí být po příjezdu"),
      else: cs
  end
end
