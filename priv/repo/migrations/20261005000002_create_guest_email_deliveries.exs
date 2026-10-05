defmodule CozyCheckout.Repo.Migrations.CreateGuestEmailDeliveries do
  use Ecto.Migration

  def change do
    create table(:guest_email_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :booking_id, references(:bookings, type: :binary_id, on_delete: :nilify_all)
      add :batch_id, :binary_id, null: false
      add :oban_job_id, references(:oban_jobs, on_delete: :nilify_all)
      add :recipient_email, :string, null: false
      add :booking_name, :string, null: false
      add :subject, :string, null: false
      add :content_mode, :string, null: false
      add :template_id, :string
      add :state, :string, null: false, default: "queued"
      add :attempt_count, :integer, null: false, default: 0
      add :started_at, :utc_datetime
      add :accepted_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :last_error, :string

      timestamps(type: :utc_datetime)
    end

    create index(:guest_email_deliveries, [:booking_id, :inserted_at])
    create index(:guest_email_deliveries, [:batch_id])
    create index(:guest_email_deliveries, [:state, :inserted_at])
    create unique_index(:guest_email_deliveries, [:oban_job_id])
  end
end
