defmodule CozyCheckout.Repo.Migrations.CreateAbraPdfTransfers do
  use Ecto.Migration

  def change do
    create table(:abra_pdf_transfers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :export_id, references(:accommodation_abra_exports, type: :binary_id), null: false
      add :state, :string, null: false, default: "queued"
      add :error, :text
      add :sha256, :string
      add :uploaded_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:abra_pdf_transfers, [:export_id])

    create constraint(:abra_pdf_transfers, :valid_pdf_transfer_state,
             check: "state IN ('queued', 'failed', 'uploaded')"
           )
  end
end
