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
        <.input field={@form[:name]} type="text" label="Template Name" required placeholder="E.g., Continental Breakfast" />

        <.input
          field={@form[:category]}
          type="select"
          label="Category"
          required
          options={[
            {"Breakfast", "breakfast"},
            {"Lunch", "lunch"},
            {"Dinner", "dinner"}
          ]}
        />

        <.input
          field={@form[:default_menu_text]}
          type="textarea"
          label="Default Menu Text"
          placeholder="E.g., Coffee, tea, juice, bread, butter, jam, cheese, ham"
          rows="4"
        />

        <div class="mt-6 flex items-center justify-end gap-x-6">
          <.button type="submit" phx-disable-with="Saving...">Save Template</.button>
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
         |> put_flash(:info, "Template updated successfully")
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
         |> put_flash(:info, "Template created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
