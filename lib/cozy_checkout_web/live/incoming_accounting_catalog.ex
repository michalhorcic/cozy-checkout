defmodule CozyCheckoutWeb.IncomingAccountingCatalog do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [connected?: 1, start_async: 3]
  alias CozyCheckout.IncomingDocuments
  alias CozyCheckout.IncomingDocuments.Batches

  def defaults do
    [accounting_catalogs: %{}, accounting_catalog_key: nil, accounting_loading: true]
  end

  def load(socket, target, kind, force \\ false) do
    key = {String.trim_trailing(target.base_url, "/"), target.company_id, target.agenda}

    cond do
      not connected?(socket) ->
        socket

      not force and socket.assigns.accounting_catalog_key == key ->
        socket

      not force and Map.has_key?(socket.assigns.accounting_catalogs, key) ->
        assign(socket,
          accounting_catalog_key: key,
          accounting_options: options(socket.assigns.accounting_catalogs[key], kind),
          accounting_loading: false,
          accounting_error: nil
        )

      true ->
        id = target.id

        socket
        |> assign(
          accounting_catalog_key: key,
          accounting_options:
            if(socket.assigns.accounting_catalog_key == key,
              do: socket.assigns.accounting_options,
              else: []
            ),
          accounting_loading: true,
          accounting_error: nil
        )
        |> start_async({:accounting_catalog, key}, fn ->
          case kind do
            :batch -> Batches.presets(id)
            :document -> IncomingDocuments.accounting_presets(id)
          end
        end)
    end
  end

  def complete(socket, key, {:ok, {:ok, rows}}, kind) do
    socket =
      assign(socket, accounting_catalogs: Map.put(socket.assigns.accounting_catalogs, key, rows))

    if socket.assigns.accounting_catalog_key == key do
      assign(socket,
        accounting_options: options(rows, kind),
        accounting_loading: false,
        accounting_error: nil
      )
    else
      socket
    end
  end

  def complete(socket, key, result, _kind) do
    message =
      case result do
        {:ok, {:error, reason}} when is_binary(reason) -> reason
        _ -> "Předpisy z ABRA se nepodařilo načíst. Zkuste to znovu."
      end

    if socket.assigns.accounting_catalog_key == key,
      do: assign(socket, accounting_loading: false, accounting_error: message),
      else: socket
  end

  defp options(rows, kind) do
    Enum.map(rows, fn row ->
      %{
        id:
          if(kind == :document,
            do: Base.url_encode64(row["kod"], padding: false),
            else: row["kod"]
          ),
        name: "#{row["kod"]} — #{row["nazev"]}",
        hint: row["protiUcetVydej"] || "Účet neurčen",
        search_text: "#{row["kod"]} #{row["nazev"]} #{row["protiUcetVydej"]}"
      }
    end)
  end
end
