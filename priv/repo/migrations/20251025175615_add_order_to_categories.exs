defmodule CozyCheckout.Repo.Migrations.AddOrderToCategories do
  use Ecto.Migration

  def change do
    # Add order column to categories table
    alter table(:categories) do
      add :order, :integer, null: false, default: 0
    end

    # Create index on order column for efficient sorting
    create index(:categories, [:order])

    # Set initial order for existing categories based on inserted_at
    execute(
      """
      UPDATE categories
      SET "order" = subquery.row_num
      FROM (
        SELECT id, ROW_NUMBER() OVER (ORDER BY inserted_at) AS row_num
        FROM categories
      ) AS subquery
      WHERE categories.id = subquery.id;
      """,
      """
      -- No-op on rollback, default values are fine
      """
    )
  end
end
