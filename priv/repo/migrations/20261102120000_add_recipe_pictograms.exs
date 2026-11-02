defmodule CozyCheckout.Repo.Migrations.AddRecipePictograms do
  use Ecto.Migration

  def change do
    alter table(:recipes) do
      add :pictogram, :string
    end

    create constraint(:recipes, :recipes_pictogram_allowed,
             check:
               "pictogram IN ('poultry', 'beef', 'pork', 'minced', 'soup', 'legumes', 'vegetables', 'pasta', 'rice', 'potatoes', 'dumplings', 'sweet', 'sauce', 'wok', 'breakfast')"
           )
  end
end
