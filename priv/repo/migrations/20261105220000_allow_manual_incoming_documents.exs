defmodule CozyCheckout.Repo.Migrations.AllowManualIncomingDocuments do
  use Ecto.Migration

  def up do
    alter table(:incoming_documents) do
      modify :original, :binary, null: true
      modify :content_type, :string, null: true
      modify :sha256, :string, null: true
    end
  end

  def down do
    execute "UPDATE incoming_documents SET original = ''::bytea, content_type = 'application/octet-stream', sha256 = '' WHERE original IS NULL"

    alter table(:incoming_documents) do
      modify :original, :binary, null: false
      modify :content_type, :string, null: false
      modify :sha256, :string, null: false
    end
  end
end
