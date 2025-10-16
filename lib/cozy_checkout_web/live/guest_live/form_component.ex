defmodule CozyCheckoutWeb.GuestLive.FormComponent do
  use CozyCheckoutWeb, :live_component

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
        id="guest-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" required />

        <.input field={@form[:room_number]} type="text" label="Room Number" />

        <.input field={@form[:phone]} type="tel" label="Phone" />

        <.input field={@form[:check_in_date]} type="date" label="Check-in Date" />

        <.input field={@form[:check_out_date]} type="date" label="Check-out Date" />

        <.input field={@form[:notes]} type="textarea" label="Notes" />

        <div class="mt-6 flex items-center justify-end gap-x-6">
          <.button type="submit" phx-disable-with="Saving...">Save Guest</.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{guest: guest} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(Guests.change_guest(guest))
     end)}
  end

  @impl true
  def handle_event("validate", %{"guest" => guest_params}, socket) do
    changeset = Guests.change_guest(socket.assigns.guest, guest_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"guest" => guest_params}, socket) do
    save_guest(socket, socket.assigns.action, guest_params)
  end

  defp save_guest(socket, :edit, guest_params) do
    case Guests.update_guest(socket.assigns.guest, guest_params) do
      {:ok, guest} ->
        notify_parent({:saved, guest})

        {:noreply,
         socket
         |> put_flash(:info, "Guest updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_guest(socket, :new, guest_params) do
    case Guests.create_guest(guest_params) do
      {:ok, guest} ->
        notify_parent({:saved, guest})

        {:noreply,
         socket
         |> put_flash(:info, "Guest created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
