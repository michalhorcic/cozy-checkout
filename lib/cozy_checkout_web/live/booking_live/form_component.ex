defmodule CozyCheckoutWeb.BookingLive.FormComponent do
  use CozyCheckoutWeb, :live_component

  alias CozyCheckout.Bookings
  alias CozyCheckout.Guests

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

        <.input field={@form[:room_number]} type="text" label="Room Number" />

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

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:guest_options, guest_options)
     |> assign_new(:form, fn ->
       to_form(Bookings.change_booking(booking))
     end)}
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
        notify_parent({:saved, booking})

        {:noreply,
         socket
         |> put_flash(:info, "Booking updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_booking(socket, :new, booking_params) do
    case Bookings.create_booking(booking_params) do
      {:ok, booking} ->
        notify_parent({:saved, booking})

        {:noreply,
         socket
         |> put_flash(:info, "Booking created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
