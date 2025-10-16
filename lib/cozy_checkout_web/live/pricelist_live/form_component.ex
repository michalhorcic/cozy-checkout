defmodule CozyCheckoutWeb.PricelistLive.FormComponent do
  use CozyCheckoutWeb, :live_component

  alias CozyCheckout.Catalog

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
      </.header>

      <.form
        for={@form}
        id="pricelist-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:product_id]}
          type="select"
          label="Product"
          prompt="Select a product"
          options={Enum.map(@products, &{&1.name, &1.id})}
          required
        />

        <.input field={@form[:price]} type="number" label="Price" step="0.01" required />

        <.input field={@form[:vat_rate]} type="number" label="VAT Rate (%)" step="0.01" required />

        <.input field={@form[:valid_from]} type="date" label="Valid From" required />

        <.input field={@form[:valid_to]} type="date" label="Valid To" />

        <.input field={@form[:active]} type="checkbox" label="Active" />

        <div class="mt-6 flex items-center justify-end gap-x-6">
          <.button type="submit" phx-disable-with="Saving...">Save Pricelist</.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{pricelist: pricelist} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:products, Catalog.list_products())
     |> assign_new(:form, fn ->
       to_form(Catalog.change_pricelist(pricelist))
     end)}
  end

  @impl true
  def handle_event("validate", %{"pricelist" => pricelist_params}, socket) do
    changeset = Catalog.change_pricelist(socket.assigns.pricelist, pricelist_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"pricelist" => pricelist_params}, socket) do
    save_pricelist(socket, socket.assigns.action, pricelist_params)
  end

  defp save_pricelist(socket, :edit, pricelist_params) do
    case Catalog.update_pricelist(socket.assigns.pricelist, pricelist_params) do
      {:ok, pricelist} ->
        notify_parent({:saved, pricelist})

        {:noreply,
         socket
         |> put_flash(:info, "Pricelist updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_pricelist(socket, :new, pricelist_params) do
    case Catalog.create_pricelist(pricelist_params) do
      {:ok, pricelist} ->
        notify_parent({:saved, pricelist})

        {:noreply,
         socket
         |> put_flash(:info, "Pricelist created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
