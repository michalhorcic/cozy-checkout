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
  Returns an `%Ecto.Changeset{}` for tracking guest changes.
  """
  def change_guest(%Guest{} = guest, attrs \\ %{}) do
    Guest.changeset(guest, attrs)
  end
end
