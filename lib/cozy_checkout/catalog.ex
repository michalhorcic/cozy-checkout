defmodule CozyCheckout.Catalog do
  @moduledoc """
  The Catalog context.
  """

  import Ecto.Query, warn: false
  alias CozyCheckout.Repo

  alias CozyCheckout.Catalog.{Category, Product, Pricelist}

  ## Categories

  @doc """
  Returns the list of categories.
  """
  def list_categories do
    Category
    |> where([c], is_nil(c.deleted_at))
    |> order_by([c], [asc: c.order, asc: c.name])
    |> Repo.all()
  end

  @doc """
  Gets a single category.
  """
  def get_category!(id) do
    Category
    |> where([c], is_nil(c.deleted_at))
    |> Repo.get!(id)
  end

  @doc """
  Creates a category.
  """
  def create_category(attrs \\ %{}) do
    # If order is not provided, set it to max order + 1
    attrs =
      if Map.has_key?(attrs, "order") || Map.has_key?(attrs, :order) do
        attrs
      else
        max_order =
          Category
          |> where([c], is_nil(c.deleted_at))
          |> select([c], max(c.order))
          |> Repo.one()

        next_order = if max_order, do: max_order + 1, else: 1
        Map.put(attrs, :order, next_order)
      end

    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a category.
  """
  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a category (soft delete).
  """
  def delete_category(%Category{} = category) do
    category
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking category changes.
  """
  def change_category(%Category{} = category, attrs \\ %{}) do
    Category.changeset(category, attrs)
  end

  ## Products

  @doc """
  Returns the list of products.
  """
  def list_products do
    Product
    |> where([p], is_nil(p.deleted_at))
    |> preload(:category)
    |> order_by([p], p.name)
    |> Repo.all()
  end

  @doc """
  Gets a single product.
  """
  def get_product!(id) do
    Product
    |> where([p], is_nil(p.deleted_at))
    |> preload(:category)
    |> Repo.get!(id)
  end

  @doc """
  Creates a product.
  """
  def create_product(attrs \\ %{}) do
    %Product{}
    |> Product.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a product.
  """
  def update_product(%Product{} = product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a product (soft delete).
  """
  def delete_product(%Product{} = product) do
    product
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking product changes.
  """
  def change_product(%Product{} = product, attrs \\ %{}) do
    Product.changeset(product, attrs)
  end

  ## Pricelists

  @doc """
  Returns the list of pricelists.
  """
  def list_pricelists do
    Pricelist
    |> where([p], is_nil(p.deleted_at))
    |> preload(:product)
    |> order_by([p], desc: p.valid_from)
    |> Repo.all()
  end

  @doc """
  Gets a single pricelist.
  """
  def get_pricelist!(id) do
    Pricelist
    |> where([p], is_nil(p.deleted_at))
    |> preload(:product)
    |> Repo.get!(id)
  end

  @doc """
  Gets the active pricelist for a product on a given date.
  """
  def get_active_pricelist_for_product(product_id, date \\ Date.utc_today()) do
    Pricelist
    |> where([p], p.product_id == ^product_id)
    |> where([p], is_nil(p.deleted_at))
    |> where([p], p.active == true)
    |> where([p], p.valid_from <= ^date)
    |> where([p], is_nil(p.valid_to) or p.valid_to >= ^date)
    |> order_by([p], desc: p.valid_from)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets the price for a product with a specific unit amount.
  Returns {:ok, price, vat_rate, pricelist} if found, {:error, reason} otherwise.
  """
  def get_price_for_product(product_id, unit_amount, date \\ Date.utc_today()) do
    case get_active_pricelist_for_product(product_id, date) do
      nil ->
        {:error, :no_active_pricelist}

      pricelist ->
        case Pricelist.get_price_for_amount(pricelist, unit_amount) do
          {:ok, price} ->
            {:ok, price, pricelist.vat_rate, pricelist}

          {:error, :no_price_for_amount} ->
            # Fallback to single price if no price tier matches
            if pricelist.price do
              {:ok, pricelist.price, pricelist.vat_rate, pricelist}
            else
              {:error, :no_price_for_amount}
            end
        end
    end
  end

  @doc """
  Creates a pricelist.
  """
  def create_pricelist(attrs \\ %{}) do
    %Pricelist{}
    |> Pricelist.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a pricelist.
  """
  def update_pricelist(%Pricelist{} = pricelist, attrs) do
    pricelist
    |> Pricelist.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a pricelist (soft delete).
  """
  def delete_pricelist(%Pricelist{} = pricelist) do
    pricelist
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking pricelist changes.
  """
  def change_pricelist(%Pricelist{} = pricelist, attrs \\ %{}) do
    Pricelist.changeset(pricelist, attrs)
  end

  @doc """
  Gets all active pricelists grouped by category for printing.
  Only includes pricelists that are active and valid for today.
  Returns a list of {category, products_with_pricelists} tuples.
  """
  def get_active_pricelists_for_print(date \\ Date.utc_today()) do
    # Get all active pricelists valid for the given date
    pricelists =
      Pricelist
      |> where([p], is_nil(p.deleted_at))
      |> where([p], p.active == true)
      |> where([p], p.valid_from <= ^date)
      |> where([p], is_nil(p.valid_to) or p.valid_to >= ^date)
      |> preload([p], product: :category)
      |> order_by([p], desc: p.valid_from)
      |> Repo.all()

    # Group by product (take most recent pricelist per product)
    pricelists_by_product =
      pricelists
      |> Enum.group_by(& &1.product_id)
      |> Enum.map(fn {_product_id, pricelists} ->
        # Take the most recent pricelist for this product
        List.first(pricelists)
      end)
      |> Enum.filter(& &1.product != nil)
      |> Enum.filter(& &1.product.active == true)

    # Group by category
    pricelists_by_product
    |> Enum.group_by(& &1.product.category)
    |> Enum.sort_by(fn {category, _} ->
      if category do
        {category.order, category.name}
      else
        {999_999, ""}
      end
    end)
    |> Enum.map(fn {category, pricelists} ->
      # Sort products alphabetically with Czech collation support
      sorted_pricelists = Enum.sort(pricelists, &compare_czech_names(&1.product.name, &2.product.name))
      {category, sorted_pricelists}
    end)
  end

  # Private helper for Czech alphabet-aware string comparison
  defp compare_czech_names(a, b) do
    normalize_czech(a) <= normalize_czech(b)
  end

  # Normalize strings for Czech collation by replacing special characters
  # with sortable equivalents that maintain proper Czech alphabetical order
  defp normalize_czech(string) do
    string
    |> String.downcase()
    |> String.replace("á", "a\x01")
    |> String.replace("č", "c\x01")
    |> String.replace("ď", "d\x01")
    |> String.replace("é", "e\x01")
    |> String.replace("ě", "e\x02")
    |> String.replace("í", "i\x01")
    |> String.replace("ň", "n\x01")
    |> String.replace("ó", "o\x01")
    |> String.replace("ř", "r\x01")
    |> String.replace("š", "s\x01")
    |> String.replace("ť", "t\x01")
    |> String.replace("ú", "u\x01")
    |> String.replace("ů", "u\x02")
    |> String.replace("ý", "y\x01")
    |> String.replace("ž", "z\x01")
  end
end
