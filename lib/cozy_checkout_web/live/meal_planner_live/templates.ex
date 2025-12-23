defmodule CozyCheckoutWeb.MealPlannerLive.Templates do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Meals
  alias CozyCheckout.Meals.MealTemplate

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :meal_templates, Meals.list_meal_templates())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Meal Template")
    |> assign(:meal_template, Meals.get_meal_template!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Meal Template")
    |> assign(:meal_template, %MealTemplate{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Meal Templates")
    |> assign(:meal_template, nil)
  end

  @impl true
  def handle_info({CozyCheckoutWeb.MealPlannerLive.TemplateFormComponent, {:saved, template}}, socket) do
    {:noreply, stream_insert(socket, :meal_templates, template)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    template = Meals.get_meal_template!(id)
    {:ok, _} = Meals.delete_meal_template(template)

    {:noreply, stream_delete(socket, :meal_templates, template)}
  end
end
