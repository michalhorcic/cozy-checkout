defmodule CozyCheckoutWeb.BookingComponents do
  @moduledoc """
  Reusable components for booking-related UI elements.
  """
  use Phoenix.Component
  import CozyCheckoutWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: CozyCheckoutWeb.Endpoint,
    router: CozyCheckoutWeb.Router,
    statics: CozyCheckoutWeb.static_paths()

  @doc """
  Renders a modal showing bookings for a specific date.

  ## Examples

      <.bookings_modal
        date={@modal_date}
        bookings={@modal_bookings}
        on_close={JS.push("close_modal")}
      />
  """
  attr :date, :any, required: true, doc: "The date to display bookings for"
  attr :bookings, :list, required: true, doc: "List of bookings for the date"
  attr :on_close, :any, required: true, doc: "JS command to execute on modal close"

  def bookings_modal(assigns) do
    ~H"""
    <.modal
      :if={@date}
      id="day-bookings-modal"
      show={@date != nil}
      on_cancel={@on_close}
    >
      <div class="mb-6">
        <h2 class="text-2xl font-bold text-primary-500">
          Bookings for {Calendar.strftime(@date, "%B %d, %Y")}
        </h2>
        <p class="mt-1 text-sm text-primary-400">
          {length(@bookings)} {if length(@bookings) == 1, do: "booking", else: "bookings"}
        </p>
      </div>

      <div class="space-y-3 max-h-[60vh] overflow-y-auto">
        <%= for booking <- @bookings do %>
          <.link
            navigate={~p"/admin/bookings/#{booking}"}
            class={[
              "block px-4 py-3 rounded-lg border-l-4 hover:shadow-md transition-all",
              booking_status_class(booking.status)
            ]}
          >
            <div class="flex items-start justify-between">
              <div class="flex-1">
                <div class="font-semibold text-primary-500 text-lg">
                  {booking.guest.name}
                </div>
                <%= if booking.room_number do %>
                  <div class="text-sm text-primary-400 mt-1">
                    <.icon name="hero-home" class="w-4 h-4 inline-block" /> Room {booking.room_number}
                  </div>
                <% end %>
                <div class="text-sm text-primary-400 mt-1">
                  <.icon name="hero-calendar" class="w-4 h-4 inline-block" />
                  {Calendar.strftime(booking.check_in_date, "%b %d")}
                  <%= if booking.check_out_date do %>
                    → {Calendar.strftime(booking.check_out_date, "%b %d")}
                  <% else %>
                    → (ongoing)
                  <% end %>
                </div>
              </div>
              <div class="ml-4">
                <span class={booking_status_badge_class(booking.status)}>
                  {String.capitalize(booking.status)}
                </span>
              </div>
            </div>
          </.link>
        <% end %>
      </div>
    </.modal>
    """
  end

  defp booking_status_class(status) do
    case status do
      "upcoming" -> "bg-tertiary-50 border-blue-400 hover:bg-tertiary-100"
      "active" -> "bg-success-light border-green-400 hover:bg-success-light"
      "completed" -> "bg-secondary-50 border-gray-400 hover:bg-secondary-100"
      "cancelled" -> "bg-error-light border-red-400 hover:bg-error-light"
      _ -> "bg-secondary-50 border-gray-400 hover:bg-secondary-100"
    end
  end

  defp booking_status_badge_class(status) do
    base = "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium"

    color =
      case status do
        "upcoming" -> "bg-tertiary-100 text-tertiary-800"
        "active" -> "bg-success-light text-success-dark"
        "completed" -> "bg-secondary-100 text-primary-500"
        "cancelled" -> "bg-error-light text-error-dark"
        _ -> "bg-secondary-100 text-primary-500"
      end

    "#{base} #{color}"
  end
end
