defmodule CozyCheckout.Repo.Migrations.AddNameToOrdersAndMakeReferencesNullable do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :name, :string
      modify :guest_id, :binary_id, null: true
      modify :booking_id, :binary_id, null: true
    end

    create index(:orders, [:name])
  end
end
