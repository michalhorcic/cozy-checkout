defmodule CozyCheckout.Repo.Migrations.AddIncomingEditedData do
  use Ecto.Migration

  def change do
    alter table(:incoming_documents) do
      add :edited_data, :map
    end
  end
end
