defmodule CozyCheckout.GuestEmails.Delivery do
  use Ecto.Schema
  import Ecto.Changeset

  alias CozyCheckout.Bookings.Booking

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @states ~w(queued sending retrying accepted failed)

  schema "guest_email_deliveries" do
    belongs_to :booking, Booking
    field :batch_id, Ecto.UUID
    field :oban_job_id, :integer
    field :recipient_email, :string
    field :booking_name, :string
    field :subject, :string
    field :content_mode, :string
    field :template_id, :string
    field :state, :string, default: "queued"
    field :attempt_count, :integer, default: 0
    field :started_at, :utc_datetime
    field :accepted_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :last_error, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :booking_id,
      :batch_id,
      :oban_job_id,
      :recipient_email,
      :booking_name,
      :subject,
      :content_mode,
      :template_id,
      :state,
      :attempt_count,
      :started_at,
      :accepted_at,
      :completed_at,
      :last_error
    ])
    |> validate_required([
      :batch_id,
      :recipient_email,
      :booking_name,
      :subject,
      :content_mode,
      :state
    ])
    |> validate_inclusion(:content_mode, ["template", "custom"])
    |> validate_inclusion(:state, @states)
    |> validate_number(:attempt_count, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:booking_id)
    |> unique_constraint(:oban_job_id)
  end
end
