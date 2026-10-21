defmodule CozyCheckoutWeb.MealPlannerLive.Variants do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Meals.{MenuPlanning, MenuVariant}
  import CozyCheckoutWeb.MealComponents

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(params, _uri, socket) do
    variant =
      case socket.assigns.live_action do
        :new -> %MenuVariant{items: []}
        :edit -> MenuPlanning.get_variant!(params["id"])
        :index -> nil
      end

    {:noreply,
     socket
     |> assign(:page_title, "Varianty menu")
     |> assign(:variant, variant)
     |> assign(:form, if(variant, do: to_form(MenuPlanning.variant_form(variant))))
     |> stream(:variants, MenuPlanning.list_variants(), reset: true)}
  end

  @impl true
  def handle_event("validate", %{"menu_variant" => params}, socket) do
    cs = MenuVariant.changeset(socket.assigns.variant, params)
    {:noreply, assign(socket, :form, to_form(cs, action: :validate))}
  end

  def handle_event("build", _, socket) do
    cs = MenuPlanning.variant_form(socket.assigns.variant, socket.assigns.form.params || %{})
    {:noreply, assign(socket, :form, to_form(cs, action: :validate))}
  end

  def handle_event("save", %{"menu_variant" => params}, socket) do
    result =
      if socket.assigns.variant.id do
        MenuPlanning.update_variant(socket.assigns.variant, params)
      else
        MenuPlanning.create_variant(params)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Varianta uložena. Již přiřazená menu zůstala beze změny.")
         |> push_patch(to: ~p"/admin/meal-planner/variants")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :form, to_form(cs))}

      {:error, :stale_variant} ->
        {:noreply,
         put_flash(socket, :error, "Variantu mezitím změnil někdo jiný. Znovu ji otevřete.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    variant = MenuPlanning.get_variant!(id)

    case MenuPlanning.delete_variant(variant) do
      {:ok, _} ->
        {:noreply, stream_delete(socket, :variants, variant)}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, "Variantu se nepodařilo archivovat. Obnovte stránku.")}
    end
  end

  def handle_event("import_reference", _, socket) do
    case MenuPlanning.import_reference_variants() do
      {:ok, counts} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Přidáno #{counts.created} variant, přeskočeno #{counts.skipped} existujících."
         )
         |> stream(:variants, MenuPlanning.list_variants(), reset: true)}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, "Varianty se nepodařilo načíst. Žádná změna nebyla uložena.")}
    end
  end
end
