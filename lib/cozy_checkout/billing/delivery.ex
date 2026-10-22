defmodule CozyCheckout.Billing.Delivery do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "billing_deliveries" do
    belongs_to :document, CozyCheckout.Billing.Document
    field :request_id, Ecto.UUID
    field :recipient, :string
    field :subject, :string
    field :body, :string
    field :consented_at, :utc_datetime
    field :state, :string, default: "queued"
    field :attempts, :integer, default: 0
    field :error, :string
    field :accepted_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:request_id, :recipient, :subject, :body, :consented_at])
    |> validate_required([:request_id, :recipient, :subject, :body, :consented_at])
    |> validate_format(:recipient, ~r/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/)
    |> validate_length(:subject, max: 200)
    |> validate_format(:subject, ~r/\A[^\r\n]+\z/)
    |> validate_length(:body, max: 20_000)
    |> unique_constraint(:request_id)
  end
end
