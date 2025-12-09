defmodule CozyCheckoutWeb.BookingLive.GuestFormComponent do
  use CozyCheckoutWeb, :live_component

  alias CozyCheckout.Guests

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        Create New Guest
        <:subtitle>Fill in the guest details to create a new guest record.</:subtitle>
      </.header>

      <.form
        for={@form}
        id="guest-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" required />
        <.input field={@form[:email]} type="email" label="Email" />
        <.input field={@form[:phone]} type="text" label="Phone" />
        <.input field={@form[:notes]} type="textarea" label="Notes" rows="3" />

        <div class="mt-6 flex items-center justify-end gap-x-6">
          <.button
            type="button"
            phx-click={JS.exec("data-cancel", to: "#guest-modal")}
            class="bg-secondary-300 hover:bg-secondary-400 text-primary-500"
          >
            Cancel
          </.button>
          <.button type="submit" phx-disable-with="Creating...">Create Guest</.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    guest = %CozyCheckout.Guests.Guest{}

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       # Pre-populate name if provided
       attrs = if assigns[:prefill_name], do: %{"name" => assigns.prefill_name}, else: %{}
       to_form(Guests.change_guest(guest, attrs))
     end)}
  end

  @impl true
  def handle_event("validate", %{"guest" => guest_params}, socket) do
    changeset = Guests.change_guest(%CozyCheckout.Guests.Guest{}, guest_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  @impl true
  def handle_event("save", %{"guest" => guest_params}, socket) do
    case Guests.create_guest(guest_params) do
      {:ok, guest} ->
        # Send update directly to the parent FormComponent
        send(self(), {:guest_created, guest})

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
