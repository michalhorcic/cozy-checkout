defmodule CozyCheckout.Abra do
  @moduledoc """
  Public API for syncing paid orders to ABRA Flexi accounting system.
  """

  alias CozyCheckout.Abra.{Client, InvoiceBuilder}
  alias CozyCheckout.Sales

  @doc """
  Syncs a single paid order to Abra Flexi as a faktura-vydana.
  Preloads all necessary associations before building the payload.
  """
  def sync_order(order_id) when is_binary(order_id) do
    order = Sales.get_order_for_abra_sync!(order_id)

    if order.abra_document_id do
      # Already synced — skip API call to prevent duplicate invoices.
      {:ok, order.abra_document_id}
    else
      payload = InvoiceBuilder.build(order)

      case Client.create_invoice(payload) do
        {:ok, abra_id} ->
          Sales.mark_order_abra_synced(order, abra_id)
          {:ok, abra_id}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
