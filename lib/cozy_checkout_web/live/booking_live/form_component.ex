defmodule CozyCheckoutWeb.BookingLive.FormComponent do
  use CozyCheckoutWeb, :live_component

  alias CozyCheckout.Bookings
  alias CozyCheckout.Guests
  alias CozyCheckout.Rooms

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
      </.header>

      <.form
        for={@form}
        id="booking-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:guest_id]}
          type="select"
          label="Guest"
          options={@guest_options}
          required
          prompt="Select a guest"
        />

        <div class="mb-4">
          <label class="block text-sm font-semibold leading-6 text-zinc-800 mb-2">
            Rooms
          </label>
          <div class="grid grid-cols-2 gap-2">
            <%= for room <- @rooms do %>
              <label class="flex items-center p-3 border rounded-lg cursor-pointer hover:bg-gray-50 transition-colors">
                <input
                  type="checkbox"
                  name="room_ids[]"
                  value={room.id}
                  checked={room.id in @selected_room_ids}
                  phx-target={@myself}
                  phx-click="toggle_room"
                  phx-value-room-id={room.id}
                  class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                />
                <span class="ml-2 text-sm text-gray-900">
                  {room.room_number}
                  <%= if room.name do %>
                    <span class="text-gray-500">- {room.name}</span>
                  <% end %>
                  <span class="text-gray-400 text-xs block">Capacity: {room.capacity}</span>
                </span>
              </label>
            <% end %>
          </div>
          <%= if @room_error do %>
            <p class="mt-2 text-sm text-rose-600">{@room_error}</p>
          <% end %>
        </div>

        <.input field={@form[:check_in_date]} type="date" label="Check-in Date" required />

        <.input field={@form[:check_out_date]} type="date" label="Check-out Date" />

        <.input
          field={@form[:status]}
          type="select"
          label="Status"
          options={[
            {"Upcoming", "upcoming"},
            {"Active", "active"},
            {"Completed", "completed"},
            {"Cancelled", "cancelled"}
          ]}
          required
        />

        <.input field={@form[:notes]} type="textarea" label="Notes" rows="3" />

        <div class="mt-6 flex items-center justify-end gap-x-6">
          <.button type="submit" phx-disable-with="Saving...">Save Booking</.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{booking: booking} = assigns, socket) do
    guests = Guests.list_guests()
    guest_options = Enum.map(guests, fn guest -> {guest.name, guest.id} end)
    rooms = Rooms.list_rooms()

    selected_room_ids =
      if booking.id do
        Bookings.list_booking_rooms(booking.id) |> Enum.map(& &1.id)
      else
        []
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:guest_options, guest_options)
     |> assign(:rooms, rooms)
     |> assign(:selected_room_ids, selected_room_ids)
     |> assign(:room_error, nil)
     |> assign_new(:form, fn ->
       to_form(Bookings.change_booking(booking))
     end)}
  end

  @impl true
  def handle_event("toggle_room", %{"room-id" => room_id}, socket) do
    selected_room_ids = socket.assigns.selected_room_ids

    selected_room_ids =
      if room_id in selected_room_ids do
        List.delete(selected_room_ids, room_id)
      else
        [room_id | selected_room_ids]
      end

    {:noreply, assign(socket, selected_room_ids: selected_room_ids, room_error: nil)}
  end

  @impl true
  def handle_event("validate", %{"booking" => booking_params}, socket) do
    changeset = Bookings.change_booking(socket.assigns.booking, booking_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"booking" => booking_params}, socket) do
    save_booking(socket, socket.assigns.action, booking_params)
  end

  defp save_booking(socket, :edit, booking_params) do
    case Bookings.update_booking(socket.assigns.booking, booking_params) do
      {:ok, booking} ->
        # Update room associations
        case Bookings.set_booking_rooms(booking.id, socket.assigns.selected_room_ids) do
          {:ok, _} ->
            notify_parent({:saved, booking})

            {:noreply,
             socket
             |> put_flash(:info, "Booking updated successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, {:rooms_not_available, _unavailable_rooms}} ->
            {:noreply,
             assign(socket, room_error: "One or more selected rooms are not available for these dates")}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_booking(socket, :new, booking_params) do
    case Bookings.create_booking(booking_params) do
      {:ok, booking} ->
        # Add room associations
        case Bookings.set_booking_rooms(booking.id, socket.assigns.selected_room_ids) do
          {:ok, _} ->
            notify_parent({:saved, booking})

            {:noreply,
             socket
             |> put_flash(:info, "Booking created successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, {:rooms_not_available, _unavailable_rooms}} ->
            # Rollback the booking creation
            Bookings.delete_booking(booking)

            {:noreply,
             assign(socket, room_error: "One or more selected rooms are not available for these dates")}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
