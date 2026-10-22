defmodule CozyCheckoutWeb.MealPlannerLive.TemplateFormComponent do
  use CozyCheckoutWeb, :live_component

  alias CozyCheckout.Meals

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
      </.header>

      <.form
        for={@form}
        id="template-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:name]}
          type="text"
          label="Název šablony"
          required
          placeholder="Např. snídaňový bufet"
        />

        <.input
          field={@form[:category]}
          type="select"
          label="Kategorie"
          required
          options={[
            {"Snídaně", "breakfast"},
            {"Oběd", "lunch"},
            {"Večeře", "dinner"}
          ]}
        />

        <.input
          field={@form[:default_menu_text]}
          type="textarea"
          label="Výchozí text menu"
          placeholder="Např. káva, čaj, pečivo, máslo, marmeláda, sýr, šunka"
          rows="4"
        />

        <div class="mt-6 flex items-center justify-end gap-x-6">
          <.button type="submit" phx-disable-with="Ukládám…">Uložit šablonu</.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{meal_template: meal_template} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(Meals.MealTemplate.changeset(meal_template, %{}))
     end)}
  end

  @impl true
  def handle_event("validate", %{"meal_template" => template_params}, socket) do
    changeset = Meals.MealTemplate.changeset(socket.assigns.meal_template, template_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"meal_template" => template_params}, socket) do
    save_template(socket, socket.assigns.action, template_params)
  end

  defp save_template(socket, :edit, template_params) do
    case Meals.update_meal_template(socket.assigns.meal_template, template_params) do
      {:ok, template} ->
        notify_parent({:saved, template})

        {:noreply,
         socket
         |> put_flash(:success, "Šablona upravena")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_template(socket, :new, template_params) do
    case Meals.create_meal_template(template_params) do
      {:ok, template} ->
        notify_parent({:saved, template})

        {:noreply,
         socket
         |> put_flash(:success, "Šablona vytvořena")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
