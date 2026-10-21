defmodule CozyCheckout.Meals.BookingMenu do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "booking_menus" do
    belongs_to :booking, CozyCheckout.Bookings.Booking
    belongs_to :menu_variant, CozyCheckout.Meals.MenuVariant
    field :variant_name, :string
    field :source_revision, :integer
    field :booking_signature, :map
    has_many :items, CozyCheckout.Meals.BookingMenuItem
    timestamps(type: :utc_datetime)
  end

  def changeset(menu, attrs) do
    menu
    |> cast(attrs, [:menu_variant_id, :variant_name, :source_revision, :booking_signature])
    |> validate_required([:menu_variant_id, :variant_name, :source_revision, :booking_signature])
    |> unique_constraint(:booking_id)
    |> foreign_key_constraint(:menu_variant_id)
  end
end
