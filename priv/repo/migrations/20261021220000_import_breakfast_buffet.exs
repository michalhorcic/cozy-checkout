defmodule CozyCheckout.Repo.Migrations.ImportBreakfastBuffet do
  use Ecto.Migration

  def up do
    data =
      Application.app_dir(:cozy_checkout, "priv/recipes/breakfast_buffet.json")
      |> File.read!()
      |> Jason.decode!()

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    {created, _} =
      repo().insert_all(
        "recipes",
        [
          %{
            id: id,
            name: data["name"],
            base_servings: Decimal.new(data["base_servings"]),
            source_key: "kitchen:breakfast-buffet:v1",
            source_reference: data["source_url"],
            notes:
              "Pracovní odhad na jednu dospělou snídani, schválený pro první vyzkoušení. Množství v listu Bufet nebyla vyplněná. Před sezonou upravte normy podle zkušenosti; nepoužívané položky nastavte na 0. Dětský koeficient se nastavuje samostatně.",
            inserted_at: now,
            updated_at: now
          }
        ],
        on_conflict: :nothing
      )

    if created == 1 do
      ingredients =
        repo().query!("SELECT name, id FROM kitchen_ingredients").rows
        |> Map.new(fn [n, id] -> {n, id} end)

      lines =
        Enum.with_index(data["lines"], fn line, i ->
          %{
            id: Ecto.UUID.generate() |> Ecto.UUID.dump!(),
            recipe_id: id,
            ingredient_id: Map.fetch!(ingredients, line["ingredient_name"]),
            quantity: Decimal.new(line["quantity"]),
            unit: line["unit"],
            position: i,
            notes: "Výchozí pracovní odhad – upravte podle zkušenosti.",
            inserted_at: now,
            updated_at: now
          }
        end)

      repo().insert_all("recipe_lines", lines)
    end

    # Respect a user-created recipe of the same name and any existing explicit links.
    for table <- ["menu_variant_items", "booking_menu_items"] do
      repo().query!(
        "UPDATE #{table} SET recipe_id = r.id FROM recipes r WHERE r.name = $1 AND #{table}.menu_text = $1 AND #{table}.recipe_id IS NULL",
        [data["name"]]
      )
    end
  end

  def down do
    for table <- ["menu_variant_supplements", "booking_menu_supplements"] do
      execute(
        "DELETE FROM #{table} WHERE recipe_id IN (SELECT id FROM recipes WHERE source_key = 'kitchen:breakfast-buffet:v1')"
      )
    end

    for table <- ["menu_variant_items", "booking_menu_items"] do
      execute(
        "UPDATE #{table} SET recipe_id = NULL WHERE recipe_id IN (SELECT id FROM recipes WHERE source_key = 'kitchen:breakfast-buffet:v1')"
      )
    end

    execute("DELETE FROM recipes WHERE source_key = 'kitchen:breakfast-buffet:v1'")
  end
end
