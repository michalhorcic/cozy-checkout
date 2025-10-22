defmodule CozyCheckoutWeb.BookingLive.ManageGuests do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Bookings
  alias CozyCheckout.Guests

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"booking_id" => booking_id}, _, socket) do
    booking = Bookings.get_booking!(booking_id)
    booking_guests = Bookings.list_booking_guests(booking_id)
    all_guests = Guests.list_guests()

    {:noreply,
     socket
     |> assign(:page_title, "Manage Guests")
     |> assign(:booking, booking)
     |> assign(:booking_guests, booking_guests)
     |> assign(:all_guests, all_guests)
     |> assign(:show_add_form, false)
     |> assign(:selected_guest_id, nil)
     |> assign(:new_guest_name, "")
     |> assign(:new_guest_email, "")
     |> assign(:new_guest_phone, "")}
  end

  @impl true
  def handle_event("show_add_form", _, socket) do
    {:noreply, assign(socket, :show_add_form, true)}
  end

  @impl true
  def handle_event("cancel_add", _, socket) do
    {:noreply,
     socket
     |> assign(:show_add_form, false)
     |> assign(:selected_guest_id, nil)
     |> assign(:new_guest_name, "")
     |> assign(:new_guest_email, "")
     |> assign(:new_guest_phone, "")}
  end

  @impl true
  def handle_event("select_existing_guest", %{"guest_id" => guest_id}, socket) do
    case Bookings.add_guest_to_booking(socket.assigns.booking.id, guest_id) do
      {:ok, _booking_guest} ->
        booking_guests = Bookings.list_booking_guests(socket.assigns.booking.id)

        {:noreply,
         socket
         |> assign(:booking_guests, booking_guests)
         |> put_flash(:info, "Guest added successfully")
         |> assign(:show_add_form, false)
         |> assign(:selected_guest_id, nil)}

      {:error, %Ecto.Changeset{errors: [booking_id_guest_id: _]}} ->
        {:noreply, put_flash(socket, :error, "This guest is already part of this booking")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to add guest")}
    end
  end

  @impl true
  def handle_event(
        "create_and_add_guest",
        %{"name" => name, "email" => email, "phone" => phone},
        socket
      ) do
    guest_attrs = %{
      "name" => name,
      "email" => if(email == "", do: nil, else: email),
      "phone" => if(phone == "", do: nil, else: phone)
    }

    case Guests.create_guest(guest_attrs) do
      {:ok, guest} ->
        case Bookings.add_guest_to_booking(socket.assigns.booking.id, guest.id) do
          {:ok, _booking_guest} ->
            booking_guests = Bookings.list_booking_guests(socket.assigns.booking.id)
            all_guests = Guests.list_guests()

            {:noreply,
             socket
             |> assign(:booking_guests, booking_guests)
             |> assign(:all_guests, all_guests)
             |> put_flash(:info, "Guest created and added successfully")
             |> assign(:show_add_form, false)
             |> assign(:new_guest_name, "")
             |> assign(:new_guest_email, "")
             |> assign(:new_guest_phone, "")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to add guest to booking")}
        end

      {:error, changeset} ->
        error_message =
          changeset.errors
          |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
          |> Enum.join(", ")

        {:noreply, put_flash(socket, :error, "Failed to create guest: #{error_message}")}
    end
  end

  @impl true
  def handle_event("remove_guest", %{"id" => booking_guest_id}, socket) do
    case Bookings.remove_guest_from_booking(booking_guest_id) do
      {:ok, _} ->
        booking_guests = Bookings.list_booking_guests(socket.assigns.booking.id)

        {:noreply,
         socket
         |> assign(:booking_guests, booking_guests)
         |> put_flash(:info, "Guest removed successfully")}

      {:error, :cannot_remove_primary_guest} ->
        {:noreply, put_flash(socket, :error, "Cannot remove the primary guest")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove guest")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <div class="mb-8">
        <.link
          navigate={~p"/admin/bookings/#{@booking}"}
          class="text-blue-600 hover:text-blue-800 mb-2 inline-block"
        >
          ← Back to Booking
        </.link>
        <h1 class="text-4xl font-bold text-gray-900">{@page_title}</h1>
        <p class="text-gray-600 mt-2">
          Booking for {@booking.guest.name} - Check-in: {Calendar.strftime(
            @booking.check_in_date,
            "%b %d, %Y"
          )}
        </p>
      </div>

      <div class="bg-white shadow-lg rounded-lg p-6">
        <div class="flex justify-between items-center mb-6">
          <h2 class="text-2xl font-bold text-gray-900">Guests ({length(@booking_guests)})</h2>
          <.button :if={!@show_add_form} phx-click="show_add_form">
            <.icon name="hero-plus" class="w-5 h-5 mr-2" /> Add Guest
          </.button>
        </div>

        <%!-- Add Guest Form --%>
        <div :if={@show_add_form} class="mb-6 p-4 bg-gray-50 rounded-lg">
          <div class="flex justify-between items-center mb-4">
            <h3 class="text-lg font-semibold text-gray-900">Add Guest</h3>
            <button
              phx-click="cancel_add"
              class="text-gray-400 hover:text-gray-600"
              type="button"
            >
              <.icon name="hero-x-mark" class="w-6 h-6" />
            </button>
          </div>

          <%!-- Select Existing Guest --%>
          <div class="mb-4">
            <label class="block text-sm font-medium text-gray-700 mb-2">
              Select Existing Guest
            </label>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-2 max-h-48 overflow-y-auto">
              <%= for guest <- @all_guests do %>
                <% is_already_added =
                  Enum.any?(@booking_guests, fn bg -> bg.guest_id == guest.id end) %>
                <button
                  :if={!is_already_added}
                  phx-click="select_existing_guest"
                  phx-value-guest_id={guest.id}
                  class="text-left p-3 border border-gray-300 rounded-lg hover:bg-blue-50 hover:border-blue-500 transition-colors"
                  type="button"
                >
                  <div class="font-medium text-gray-900">{guest.name}</div>
                  <div :if={guest.email} class="text-sm text-gray-500">{guest.email}</div>
                </button>
              <% end %>
            </div>
          </div>

          <div class="border-t border-gray-300 my-4 pt-4">
            <p class="text-sm font-medium text-gray-700 mb-3">Or Create New Guest</p>
            <form phx-submit="create_and_add_guest" class="space-y-3">
              <div>
                <.input
                  type="text"
                  name="name"
                  label="Name"
                  value={@new_guest_name}
                  required
                  placeholder="Guest name"
                />
              </div>
              <div class="grid grid-cols-2 gap-3">
                <.input
                  type="email"
                  name="email"
                  label="Email (optional)"
                  value={@new_guest_email}
                  placeholder="guest@example.com"
                />
                <.input
                  type="text"
                  name="phone"
                  label="Phone (optional)"
                  value={@new_guest_phone}
                  placeholder="+1234567890"
                />
              </div>
              <.button type="submit" class="w-full">
                <.icon name="hero-plus" class="w-5 h-5 mr-2" /> Create and Add Guest
              </.button>
            </form>
          </div>
        </div>

        <%!-- Guests List --%>
        <div class="space-y-3">
          <%= for booking_guest <- @booking_guests do %>
            <div class="flex items-center justify-between p-4 border border-gray-200 rounded-lg hover:bg-gray-50">
              <div class="flex items-center space-x-3">
                <%= if booking_guest.is_primary do %>
                  <span class="px-3 py-1 bg-blue-100 text-blue-800 text-xs font-semibold rounded-full">
                    PRIMARY
                  </span>
                <% end %>
                <div>
                  <p class="font-medium text-gray-900">{booking_guest.guest.name}</p>
                  <div class="flex items-center space-x-4 text-sm text-gray-500">
                    <span :if={booking_guest.guest.email}>
                      <.icon name="hero-envelope" class="w-4 h-4 inline" />
                      {booking_guest.guest.email}
                    </span>
                    <span :if={booking_guest.guest.phone}>
                      <.icon name="hero-phone" class="w-4 h-4 inline" />
                      {booking_guest.guest.phone}
                    </span>
                  </div>
                </div>
              </div>
              <button
                :if={!booking_guest.is_primary}
                phx-click="remove_guest"
                phx-value-id={booking_guest.id}
                data-confirm="Are you sure you want to remove this guest from the booking?"
                class="text-red-600 hover:text-red-800"
                type="button"
              >
                <.icon name="hero-trash" class="w-5 h-5" />
              </button>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
