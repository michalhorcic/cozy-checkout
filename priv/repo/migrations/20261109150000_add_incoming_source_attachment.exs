defmodule CozyCheckout.Repo.Migrations.AddIncomingSourceAttachment do
  use Ecto.Migration

  def change do
    alter table(:incoming_documents) do
      add :source_attachment, :map, null: false, default: %{}
    end
  end
end
