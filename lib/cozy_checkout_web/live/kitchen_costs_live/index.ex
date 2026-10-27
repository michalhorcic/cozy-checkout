defmodule CozyCheckoutWeb.KitchenCostsLive.Index do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.{KitchenCosts, Recipes}
  alias CozyCheckout.KitchenCosts.{Import, Purchase}
  import CozyCheckoutWeb.KitchenCostsLive.Helpers

  @receipt_fields ~w(merchant purchased_on document_number total_paid rounding)
  @line_fields ~w(line_number source_name classification ingredient_id quantity unit package_count package_quantity package_unit line_total confirmed_ingredient_id remember)

  @impl true
  def mount(_, _, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Nákupy kuchyně")
     |> assign(:food_context, %{})
     |> assign(:ingredients, Recipes.list_ingredients())
     |> assign(:mapping_editor, nil)}
  end

  @impl true
  def handle_params(params, _, socket) do
    purchase = if params["id"], do: KitchenCosts.get_purchase!(params["id"])
    attrs = if purchase, do: purchase_attrs(purchase), else: blank_purchase()

    attrs =
      if socket.assigns.live_action == :edit,
        do: Map.put(attrs, "import_id", Ecto.UUID.generate()),
        else: attrs

    {:noreply,
     socket
     |> assign(:purchase, purchase)
     |> assign(:replaces_id, if(socket.assigns.live_action == :edit, do: purchase.id))
     |> assign(:purchases, KitchenCosts.list_purchases())
     |> assign(:mappings, KitchenCosts.list_mappings())
     |> assign(:unassigned, KitchenCosts.list_unassigned_lines())
     |> assign(:error, nil)
     |> assign(:import_form, to_form(%{"json" => ""}, as: :import))
     |> assign(:import_items, [])
     |> assign(:warnings, [])
     |> assign(:discount, "0")
     |> assign_draft(attrs, true)}
  end

  @impl true
  def handle_event("import", %{"import" => %{"json" => json}}, socket) do
    case Import.parse(json) do
      {:ok, parsed} ->
        lines =
          Enum.map(parsed.attrs["lines"], fn line ->
            case KitchenCosts.mapping_for(parsed.attrs["merchant"], line["source_name"]) do
              nil ->
                line

              mapping ->
                line
                |> Map.put("ingredient_id", mapping.ingredient_id)
                |> Map.put("classification", "ingredient")
            end
          end)

        attrs = Map.put(parsed.attrs, "lines", lines)

        attrs =
          if socket.assigns.replaces_id,
            do: Map.put(attrs, "import_id", Ecto.UUID.generate()),
            else: attrs

        {:noreply,
         socket
         |> assign(:error, nil)
         |> assign(:warnings, parsed.warnings)
         |> assign(:import_items, parsed.items)
         |> assign(:discount, parsed.shared_discount)
         |> assign(:import_form, to_form(%{"json" => json}, as: :import))
         |> assign_draft(attrs, true)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error(reason))}
    end
  end

  def handle_event("validate", %{"purchase" => attrs}, socket) do
    {:noreply, socket |> assign(:error, nil) |> assign_draft(merge_attrs(socket, attrs))}
  end

  def handle_event("refresh_mappings", _, socket) do
    attrs =
      Map.update!(socket.assigns.attrs, "lines", fn lines ->
        Enum.map(lines, &Map.delete(&1, "confirmed_ingredient_id"))
      end)

    {:noreply, socket |> assign(:error, nil) |> assign_draft(attrs, true)}
  end

  def handle_event("add_line", _, socket) do
    lines = socket.assigns.attrs["lines"]

    next =
      Enum.map(lines, &(to_string(&1["line_number"]) |> String.to_integer()))
      |> Enum.max(fn -> 0 end)
      |> Kernel.+(1)

    {:noreply,
     assign_draft(socket, Map.put(socket.assigns.attrs, "lines", lines ++ [blank_line(next)]))}
  end

  def handle_event("remove_line", %{"index" => index}, socket) do
    {:noreply,
     assign_draft(
       socket,
       Map.update!(socket.assigns.attrs, "lines", &List.delete_at(&1, String.to_integer(index)))
     )}
  end

  def handle_event("distribute_discount", %{"discount" => %{"amount" => amount}}, socket) do
    case Import.distribute_discount(socket.assigns.attrs["lines"], amount) do
      {:ok, lines} ->
        {:noreply,
         socket
         |> assign(:discount, "0")
         |> assign(:error, nil)
         |> assign_draft(Map.put(socket.assigns.attrs, "lines", lines))}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error(reason))}
    end
  end

  def handle_event("discount_applied", _, socket), do: {:noreply, assign(socket, :discount, "0")}

  def handle_event("save", %{"purchase" => params}, socket) do
    attrs = merge_attrs(socket, params)
    discount_applied? = match?({%Decimal{coef: 0}, ""}, Decimal.parse(socket.assigns.discount))

    result =
      if discount_applied?,
        do:
          KitchenCosts.confirm_reviewed_purchase(attrs,
            replaces_id: socket.assigns.replaces_id,
            allow_duplicate: params["allow_duplicate"] == "true",
            mapping_versions: socket.assigns.mapping_versions
          ),
        else: {:error, "Nejprve vyřešte společnou slevu."}

    case result do
      {:ok, purchase} ->
        {:noreply,
         socket
         |> put_flash(:success, "Nákup potvrzen.")
         |> push_navigate(to: ~p"/admin/kitchen-costs/#{purchase.id}")}

      {:error, reason} ->
        {:noreply, socket |> assign_draft(attrs) |> assign(:error, error(reason))}
    end
  end

  def handle_event("edit_mapping", %{"id" => id}, socket) do
    mapping = Enum.find(socket.assigns.mappings, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:mapping_editor, mapping)
     |> assign(:mapping_form, to_form(%{"ingredient_id" => mapping.ingredient_id}, as: :mapping))}
  end

  def handle_event("save_mapping", %{"mapping" => p}, socket) do
    m = socket.assigns.mapping_editor

    case KitchenCosts.set_mapping(
           m.merchant_key,
           m.source_name,
           p["ingredient_id"],
           m.lock_version
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:mapping_editor, nil)
         |> assign(:mappings, KitchenCosts.list_mappings())
         |> put_flash(:success, "Slovník upraven pro další nákupy.")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error(reason))}
    end
  end

  defp assign_draft(socket, attrs, refresh \\ false) do
    mappings =
      Map.new(attrs["lines"], fn line ->
        {to_string(line["line_number"]),
         KitchenCosts.mapping_for(attrs["merchant"], line["source_name"])}
      end)

    versions = KitchenCosts.mapping_versions(attrs)

    versions =
      if refresh,
        do: versions,
        else: Map.merge(versions, Map.get(socket.assigns, :mapping_versions, %{}))

    socket
    |> assign(:attrs, attrs)
    |> assign(:form, to_form(attrs, as: :purchase))
    |> assign(:line_mappings, mappings)
    |> assign(:mapping_versions, versions)
  end

  defp merge_attrs(socket, params) do
    lines =
      KitchenCosts.review_lines(params["lines"] || [])
      |> Enum.map(&Map.take(&1, @line_fields))
      |> Enum.map(fn line ->
        if line["classification"] in ["other", "unassigned"],
          do:
            line
            |> Map.put("ingredient_id", "")
            |> Map.delete("confirmed_ingredient_id")
            |> Map.put("remember", "false"),
          else: line
      end)

    socket.assigns.attrs
    |> Map.merge(Map.take(params, @receipt_fields))
    |> Map.put("allow_duplicate", params["allow_duplicate"] || "false")
    |> Map.put("lines", lines)
  end

  defp blank_purchase,
    do: %{
      "import_id" => Ecto.UUID.generate(),
      "merchant" => "",
      "purchased_on" => Date.to_iso8601(Date.utc_today()),
      "document_number" => "",
      "currency" => "CZK",
      "total_paid" => "",
      "rounding" => "0",
      "lines" => [blank_line(1)]
    }

  defp blank_line(number),
    do: %{
      "line_number" => number,
      "source_name" => "",
      "classification" => "unassigned",
      "ingredient_id" => "",
      "quantity" => "",
      "unit" => "kg",
      "line_total" => ""
    }

  defp purchase_attrs(p) do
    attrs =
      Map.new(@receipt_fields ++ ~w(import_id currency original_json), fn key ->
        value = Map.get(p, String.to_existing_atom(key))

        {key,
         if(is_struct(value, Decimal) or is_struct(value, Date),
           do: to_string(value),
           else: value
         )}
      end)

    lines =
      Enum.map(p.lines, fn line ->
        Map.new(
          ~w(line_number source_name classification ingredient_id quantity unit package_count package_quantity package_unit line_total),
          fn key ->
            v = Map.get(line, String.to_existing_atom(key))
            {key, if(is_struct(v, Decimal), do: to_string(v), else: v)}
          end
        )
      end)

    Map.put(attrs, "lines", lines)
  end

  defp ingredient_options(ingredients),
    do: Enum.map(ingredients, &{"#{&1.name} (#{&1.base_unit})", &1.id})

  defp proposal(items, number),
    do:
      Enum.find(
        items,
        &(&1["line_number"] == number or to_string(&1["line_number"]) == to_string(number))
      )

  defp validation_errors(attrs), do: Purchase.changeset(%Purchase{}, attrs)
end
