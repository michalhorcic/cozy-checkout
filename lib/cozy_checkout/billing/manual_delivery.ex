defmodule CozyCheckout.Billing.ManualDelivery do
  @moduledoc "External sending records; corrections preserve the original date and note."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "billing_manual_deliveries" do
    belongs_to :document, CozyCheckout.Billing.Document
    belongs_to :replaces, __MODULE__
    field :request_id, Ecto.UUID
    field :sent_on, :date
    field :note, :string
    field :voided_at, :utc_datetime
    field :void_reason, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:request_id, :sent_on, :note])
    |> validate_required([:request_id, :sent_on])
    |> validate_length(:note, max: 2000)
    |> validate_change(:sent_on, fn :sent_on, date ->
      if Date.compare(date, CozyCheckout.Billing.today()) == :gt,
        do: [sent_on: "Datum odeslání nesmí být v budoucnosti"],
        else: []
    end)
    |> unique_constraint(:request_id)
    |> unique_constraint(:replaces_id)
  end
end
