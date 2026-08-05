defmodule CozyCheckout.Repo.Migrations.AddVisibleInPosToCategories do
  use Ecto.Migration

  def change do
    alter table(:categories) do
      add :visible_in_pos, :boolean, default: true, null: false
    end
  end
end
