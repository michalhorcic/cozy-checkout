defmodule CozyCheckout.Repo.Migrations.AddIncomingExtractionData do
  use Ecto.Migration

  def change do
    alter table(:incoming_documents) do
      add :extracted_data, :map, null: false, default: %{}
      add :extraction_metadata, :map, null: false, default: %{}
      add :extraction_attempts, :integer, null: false, default: 0
    end

    create constraint(:incoming_documents, :incoming_extraction_attempts,
             check: "extraction_attempts BETWEEN 0 AND 2"
           )
  end
end
