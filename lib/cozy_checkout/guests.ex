defmodule CozyCheckout.Guests do
  @moduledoc """
  The Guests context.
  """

  import Ecto.Query, warn: false
  alias CozyCheckout.Repo

  alias CozyCheckout.Guests.Guest

  @doc """
  Returns the list of guests.
  """
  def list_guests do
    Guest
    |> where([g], is_nil(g.deleted_at))
    |> order_by([g], desc: g.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single guest.
  """
  def get_guest!(id) do
    Guest
    |> where([g], is_nil(g.deleted_at))
    |> Repo.get!(id)
  end

  @doc """
  Creates a guest.
  """
  def create_guest(attrs \\ %{}) do
    %Guest{}
    |> Guest.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a guest.
  """
  def update_guest(%Guest{} = guest, attrs) do
    guest
    |> Guest.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a guest (soft delete).
  """
  def delete_guest(%Guest{} = guest) do
    guest
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  @doc """
  Searches for guests by name and email.
  Requires at least 3 characters to search.
  Returns up to 10 matching guests.
  """
  def search_guests(query) when is_binary(query) do
    trimmed_query = String.trim(query)

    if String.length(trimmed_query) < 3 do
      []
    else
      search_pattern = "%#{trimmed_query}%"

      Guest
      |> where([g], is_nil(g.deleted_at))
      |> where(
        [g],
        ilike(g.name, ^search_pattern) or ilike(g.email, ^search_pattern)
      )
      |> order_by([g], asc: g.name)
      |> limit(10)
      |> Repo.all()
    end
  end

  def search_guests(_), do: []

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking guest changes.
  """
  def change_guest(%Guest{} = guest, attrs \\ %{}) do
    Guest.changeset(guest, attrs)
  end
end
