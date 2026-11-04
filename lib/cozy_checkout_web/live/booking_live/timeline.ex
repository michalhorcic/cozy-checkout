defmodule CozyCheckoutWeb.BookingLive.Timeline do
  use CozyCheckoutWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Časová osa skupin")}
  end
end
