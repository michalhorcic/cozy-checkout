defmodule CozyCheckout.Recipes.Recipe do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "recipes" do
    field :name, :string
    field :base_servings, :decimal, default: Decimal.new("4")
    field :source_reference, :string
    field :notes, :string
    field :source_key, :string
    field :archived_at, :utc_datetime
    field :lock_version, :integer, default: 1
    has_many :lines, CozyCheckout.Recipes.RecipeLine, on_replace: :delete
    timestamps(type: :utc_datetime)
  end

  def changeset(recipe, attrs, validate_line \\ fn line -> line end) do
    recipe
    |> cast(attrs, [:name, :base_servings, :source_reference, :notes])
    |> validate_required([:name, :base_servings])
    |> validate_length(:name, max: 250)
    |> validate_number(:base_servings, greater_than: 0)
    |> validate_length(:source_reference, max: 4000)
    |> cast_assoc(:lines,
      with: fn line, attrs, position ->
        CozyCheckout.Recipes.RecipeLine.changeset(line, attrs)
        |> put_change(:position, position)
        |> validate_line.()
      end,
      sort_param: :lines_sort,
      drop_param: :lines_drop
    )
    |> validate_lines()
    |> unique_constraint(:name, name: :recipes_name_index)
  end

  defp validate_lines(cs) do
    if get_field(cs, :lines, []) == [],
      do: add_error(cs, :lines, "Přidejte alespoň jednu surovinu"),
      else: cs
  end
end
