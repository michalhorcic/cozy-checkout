defmodule CozyCheckout.Repo.Migrations.AddRecipeMenuReview do
  use Ecto.Migration

  def up do
    for table <- [:menu_variant_items, :booking_menu_items] do
      alter table(table) do
        modify :menu_text, :text, null: true
        add :note, :text
        add :recipe_links_reviewed_at, :utc_datetime
      end
    end

    # Preserve every existing link and all original wording. Only exact, unambiguous
    # matches may fill missing links. Conflicting wording remains for human review.
    for {table, links, parent} <- [
          {"menu_variant_items", "menu_variant_supplements", "menu_variant_item_id"},
          {"booking_menu_items", "booking_menu_supplements", "booking_menu_item_id"}
        ] do
      execute """
      UPDATE #{table} i SET recipe_id = r.id FROM recipes r
      WHERE i.recipe_links_reviewed_at IS NULL AND i.recipe_id IS NULL AND i.menu_text = r.name AND r.archived_at IS NULL
      """

      execute """
      INSERT INTO #{links} (id, #{parent}, recipe_id, position, inserted_at, updated_at)
      SELECT gen_random_uuid(), i.id, r.id, s.position - 1, NOW(), NOW()
      FROM #{table} i
      CROSS JOIN LATERAL unnest(string_to_array(coalesce(i.supplements, ''), E'\n'))
        WITH ORDINALITY s(label, position)
      JOIN recipes r ON r.name = trim(regexp_replace(s.label, '^Polévka k (obědu|večeři):\\s*', ''))
        AND r.archived_at IS NULL
      WHERE i.recipe_links_reviewed_at IS NULL AND r.id IS DISTINCT FROM i.recipe_id
        AND NOT EXISTS (SELECT 1 FROM #{links} old WHERE old.#{parent} = i.id)
      ON CONFLICT DO NOTHING
      """

      execute """
      UPDATE #{table} i SET recipe_links_reviewed_at = NOW()
      FROM recipes r
      WHERE i.recipe_links_reviewed_at IS NULL AND i.recipe_id = r.id AND i.menu_text = r.name
        AND NOT EXISTS (
          SELECT 1 FROM unnest(string_to_array(coalesce(i.supplements, ''), E'\n')) s(label)
          WHERE trim(s.label) <> '' AND NOT EXISTS (
            SELECT 1 FROM #{links} l JOIN recipes extra ON extra.id = l.recipe_id
            WHERE l.#{parent} = i.id
              AND extra.name = trim(regexp_replace(s.label, '^Polévka k (obědu|večeři):\\s*', ''))
          )
        )
        AND (SELECT count(*) FROM #{links} l WHERE l.#{parent} = i.id) = (
          SELECT count(*) FROM unnest(string_to_array(coalesce(i.supplements, ''), E'\n')) s(label)
          WHERE trim(s.label) <> ''
        )
      """
    end
  end

  def down do
    for table <- [:menu_variant_items, :booking_menu_items] do
      execute "UPDATE #{table} SET menu_text = '' WHERE menu_text IS NULL"

      alter table(table) do
        modify :menu_text, :text, null: false
        remove :note
        remove :recipe_links_reviewed_at
      end
    end
  end
end
