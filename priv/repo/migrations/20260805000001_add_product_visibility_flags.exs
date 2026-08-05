defmodule CozyCheckout.Repo.Migrations.AddProductVisibilityFlags do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :track_stock, :boolean, default: true, null: false
      add :visible_in_pos, :boolean, default: true, null: false
    end
  end
end
