defmodule CozyCheckout.Repo.Migrations.AddIncomingBatchArchive do
  use Ecto.Migration

  def change do
    alter table(:incoming_document_batches) do
      add :archived_at, :utc_datetime
    end
  end
end
