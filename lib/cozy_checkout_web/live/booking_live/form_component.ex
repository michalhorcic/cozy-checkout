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
        <div class="mb-4">
          <label class="block text-sm font-semibold leading-6 text-zinc-800 mb-2">
            Guest <span class="text-rose-600">*</span>
          </label>
          <div class="relative" phx-click-away={JS.hide(to: "#guest-suggestions")}>
            <input
              type="text"
              id="guest-search"
              name="guest_search"
              value={@guest_search_text}
              placeholder="Type at least 3 characters to search..."
              phx-target={@myself}
              phx-keyup="search_guest"
              phx-debounce="300"
              autocomplete="off"
              class="mt-2 block w-full rounded-lg text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6 phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400 border-zinc-300 focus:border-zinc-400"
            />
            <input type="hidden" name="booking[guest_id]" value={@selected_guest_id} />

            <%= if @show_suggestions do %>
              <div
                id="guest-suggestions"
                class="absolute z-10 mt-1 w-full bg-white shadow-lg max-h-60 rounded-md py-1 text-base ring-1 ring-black ring-opacity-5 overflow-auto focus:outline-none sm:text-sm"
              >
                <%= if @guest_suggestions == [] and String.length(@guest_search_text) >= 3 do %>
                  <div
                    class="cursor-pointer select-none relative py-3 pl-3 pr-9 hover:bg-indigo-600 hover:text-white transition-colors"
                    phx-click="show_create_guest_modal"
                    phx-target={@myself}
                  >
                    <div class="flex items-center">
                      <span class="font-semibold text-lg mr-2">+</span>
                      <span>Create new guest: {@guest_search_text}</span>
                    </div>
                  </div>
                <% else %>
                  <%= for guest <- @guest_suggestions do %>
                    <div
                      class="cursor-pointer select-none relative py-2 pl-3 pr-9 hover:bg-indigo-600 hover:text-white transition-colors"
                      phx-click="select_guest"
                      phx-value-guest-id={guest.id}
                      phx-value-guest-name={guest.name}
                      phx-target={@myself}
                    >
                      <div class="flex flex-col">
                        <span class="font-medium">{guest.name}</span>
                        <%= if guest.email do %>
                          <span class="text-sm opacity-75">{guest.email}</span>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                  <%= if String.length(@guest_search_text) >= 3 do %>
                    <div
                      class="cursor-pointer select-none relative py-3 pl-3 pr-9 hover:bg-indigo-600 hover:text-white transition-colors border-t"
                      phx-click="show_create_guest_modal"
                      phx-target={@myself}
                    >
                      <div class="flex items-center">
                        <span class="font-semibold text-lg mr-2">+</span>
                        <span>Create new guest</span>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>
            <% end %>

            <%= if @selected_guest_name do %>
              <div class="mt-2 inline-flex items-center gap-2 px-3 py-1 bg-indigo-100 text-indigo-800 rounded-full text-sm">
                <span>{@selected_guest_name}</span>
                <button
                  type="button"
                  phx-click="clear_guest"
                  phx-target={@myself}
                  class="hover:text-indigo-600"
                >
                  <.icon name="hero-x-mark" class="w-4 h-4" />
                </button>
              </div>
            <% end %>

            <%= if @form[:guest_id].errors != [] do %>
              <p class="mt-2 text-sm text-rose-600">
                {translate_error(List.first(@form[:guest_id].errors))}
              </p>
            <% end %>
          </div>
        </div>

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

      <.modal
        :if={@show_guest_modal}
        id="guest-modal"
        show
        on_cancel={JS.push("hide_create_guest_modal", target: @myself)}
      >
        <.live_component
          module={CozyCheckoutWeb.BookingLive.GuestFormComponent}
          id={:new_guest}
          title="Create New Guest"
          action={:new}
          prefill_name={@guest_search_text}
        />
      </.modal>
    </div>
    """
  end

  @impl true
  def update(%{booking: booking} = assigns, socket) do
    rooms = Rooms.list_rooms()

    selected_room_ids =
      if booking.id do
        Bookings.list_booking_rooms(booking.id) |> Enum.map(& &1.id)
      else
        []
      end

    # Pre-populate guest search if editing
    {guest_search_text, selected_guest_id, selected_guest_name} =
      if booking.guest_id do
        guest = Guests.get_guest!(booking.guest_id)
        {guest.name, guest.id, guest.name}
      else
        {"", nil, nil}
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:rooms, rooms)
     |> assign(:selected_room_ids, selected_room_ids)
     |> assign(:room_error, nil)
     |> assign(:guest_search_text, guest_search_text)
     |> assign(:guest_suggestions, [])
     |> assign(:show_suggestions, false)
     |> assign(:selected_guest_id, selected_guest_id)
     |> assign(:selected_guest_name, selected_guest_name)
     |> assign(:show_guest_modal, false)
     |> assign_new(:form, fn ->
       to_form(Bookings.change_booking(booking))
     end)}
  end

  @impl true
  def update(%{guest_created: guest}, socket) do
    # Handle guest creation from the modal
    {:ok,
     socket
     |> assign(:selected_guest_id, guest.id)
     |> assign(:selected_guest_name, guest.name)
     |> assign(:guest_search_text, guest.name)
     |> assign(:show_guest_modal, false)
     |> put_flash(:info, "Guest created successfully")}
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
  def handle_event("search_guest", %{"value" => query}, socket) do
    suggestions = Guests.search_guests(query)
    show_suggestions = String.length(query) >= 3

    {:noreply,
     socket
     |> assign(:guest_search_text, query)
     |> assign(:guest_suggestions, suggestions)
     |> assign(:show_suggestions, show_suggestions)}
  end

  @impl true
  def handle_event("select_guest", %{"guest-id" => guest_id, "guest-name" => guest_name}, socket) do
    {:noreply,
     socket
     |> assign(:selected_guest_id, guest_id)
     |> assign(:selected_guest_name, guest_name)
     |> assign(:guest_search_text, guest_name)
     |> assign(:show_suggestions, false)
     |> assign(:guest_suggestions, [])}
  end

  @impl true
  def handle_event("clear_guest", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_guest_id, nil)
     |> assign(:selected_guest_name, nil)
     |> assign(:guest_search_text, "")
     |> assign(:show_suggestions, false)
     |> assign(:guest_suggestions, [])}
  end

  @impl true
  def handle_event("show_create_guest_modal", _params, socket) do
    {:noreply, assign(socket, show_guest_modal: true, show_suggestions: false)}
  end

  @impl true
  def handle_event("hide_create_guest_modal", _params, socket) do
    {:noreply, assign(socket, show_guest_modal: false)}
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
    # Ensure guest_id is set from the autocomplete selection
    booking_params = Map.put(booking_params, "guest_id", socket.assigns.selected_guest_id)

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
             assign(socket,
               room_error: "One or more selected rooms are not available for these dates"
             )}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_booking(socket, :new, booking_params) do
    # Ensure guest_id is set from the autocomplete selection
    booking_params = Map.put(booking_params, "guest_id", socket.assigns.selected_guest_id)

    case Bookings.create_booking(booking_params) do
      {:ok, booking} ->
        # Add room associations
        case Bookings.set_booking_rooms(booking.id, socket.assigns.selected_room_ids) do
          {:ok, _} ->
            notify_parent({:saved, booking})

            {:noreply,
             socket
             |> put_flash(:info, "Booking created successfully")
             |> push_navigate(to: ~p"/admin/bookings/#{booking}")}

          {:error, {:rooms_not_available, _unavailable_rooms}} ->
            # Rollback the booking creation
            Bookings.delete_booking(booking)

            {:noreply,
             assign(socket,
               room_error: "One or more selected rooms are not available for these dates"
             )}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
