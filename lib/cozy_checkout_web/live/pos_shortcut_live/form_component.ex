defmodule CozyCheckoutWeb.PosShortcutLive.FormComponent do
  use CozyCheckoutWeb, :live_component

  alias CozyCheckout.Catalog

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>{@title}</.header>
      <.form
        for={@form}
        id="pos-shortcut-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:product_id]}
          type="select"
          label="Product"
          prompt="Choose a product"
          options={Enum.map(@products, &{&1.name, &1.id})}
          required
        />
        <.input
          field={@form[:unit_amount]}
          type="select"
          label="Fixed size (optional)"
          options={amount_options(@selected_product)}
        />
        <p class="-mt-4 mb-4 text-sm text-primary-400">
          A fixed size is available only when configured as a default amount on the product. Without one, the POS will ask for a size.
        </p>
        <.input
          field={@form[:position]}
          type="number"
          label="Position (lower numbers appear first)"
          min="0"
          required
        />
        <div class="mt-6 flex justify-end">
          <button
            type="submit"
            phx-disable-with="Saving..."
            class="rounded-lg bg-tertiary-600 px-5 py-3 font-semibold text-white transition-colors hover:bg-tertiary-700"
          >
            Save shortcut
          </button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{shortcut: shortcut} = assigns, socket) do
    selected_product = Enum.find(assigns.products, &(&1.id == shortcut.product_id))

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:selected_product, selected_product)
     |> assign_new(:form, fn -> to_form(Catalog.change_pos_shortcut(shortcut)) end)}
  end

  @impl true
  def handle_event("validate", %{"pos_product_shortcut" => params}, socket) do
    selected_product = Enum.find(socket.assigns.products, &(&1.id == params["product_id"]))
    previous_product = socket.assigns.selected_product

    params =
      if selected_product && selected_product.id != (previous_product && previous_product.id) do
        Map.put(params, "unit_amount", "")
      else
        params
      end

    changeset = Catalog.change_pos_shortcut(socket.assigns.shortcut, params)

    {:noreply,
     socket
     |> assign(:selected_product, selected_product)
     |> assign(:form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"pos_product_shortcut" => params}, socket) do
    save_shortcut(socket, socket.assigns.action, params)
  end

  defp save_shortcut(socket, :new, params) do
    case Catalog.create_pos_shortcut(params) do
      {:ok, shortcut} -> saved(socket, shortcut)
      {:error, changeset} -> {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_shortcut(socket, :edit, params) do
    case Catalog.update_pos_shortcut(socket.assigns.shortcut, params) do
      {:ok, shortcut} -> saved(socket, shortcut)
      {:error, changeset} -> {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp saved(socket, shortcut) do
    send(self(), {__MODULE__, {:saved, shortcut}})

    {:noreply,
     socket
     |> put_flash(:info, "POS shortcut saved.")
     |> push_patch(to: socket.assigns.patch)}
  end

  defp amount_options(nil), do: [{"Choose on POS", ""}]

  defp amount_options(product) do
    [{"Choose on POS", ""}] ++
      (product.default_unit_amounts
       |> parse_amounts()
       |> Enum.map(fn amount ->
         value = amount |> to_string() |> Decimal.new() |> Decimal.round(2) |> Decimal.to_string()
         {"#{amount} #{product.unit}", value}
       end))
  end

  defp parse_amounts(nil), do: []
  defp parse_amounts(""), do: []

  defp parse_amounts(encoded) do
    case Jason.decode(encoded) do
      {:ok, amounts} when is_list(amounts) -> Enum.filter(amounts, &is_number/1)
      _ -> []
    end
  end
end
