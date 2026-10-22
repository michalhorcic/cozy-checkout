defmodule CozyCheckoutWeb.AdminNavigation do
  @moduledoc "Shared admin navigation and route tracking across the authenticated LiveView session."
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> assign(:admin_path, "/admin")
     |> attach_hook(:admin_navigation, :handle_params, fn _params, uri, socket ->
       {:cont, assign(socket, :admin_path, URI.parse(uri).path)}
     end)}
  end

  def primary do
    [
      {"Přehled", "/admin", "hero-squares-2x2"},
      {"Rezervace", "/admin/bookings/calendar", "hero-calendar-days"},
      {"Stravování", "/admin/meal-planner", "hero-clipboard-document-list"},
      {"Barový sklad", "/admin/bar-stock", "hero-beaker"},
      {"Emaily hostům", "/admin/emails", "hero-envelope"},
      {"Barové účty a platby", "/admin/orders", "hero-banknotes"}
    ]
  end

  def groups do
    [
      {"Pobyty a hosté",
       [
         {"Seznam rezervací", "/admin/bookings"},
         {"Časová osa", "/admin/bookings/timeline"},
         {"Hosté", "/admin/guests"},
         {"Pokoje", "/admin/rooms"},
         {"Import rezervací", "/admin/ical-import"}
       ]},
      {"Skladová evidence",
       [
         {"Celkový sklad", "/admin/stock"},
         {"Naskladnění", "/admin/stock/restock"},
         {"Nákupní objednávky", "/admin/purchase_orders"},
         {"Skladové korekce", "/admin/stock-adjustments"},
         {"Skladové reporty", "/admin/inventory-reports"}
       ]},
      {"Produkty a ceny",
       [
         {"Produkty", "/admin/products"},
         {"Kategorie", "/admin/categories"},
         {"Správa cen", "/admin/pricelists/management"},
         {"Jednotlivé ceníky", "/admin/pricelists"},
         {"Tisk ceníku", "/admin/pricelists/print"},
         {"Zkratky pokladny", "/admin/pos-shortcuts"}
       ]},
      {"Finance a přehledy",
       [
         {"Barové platby", "/admin/payments"},
         {"Ekonomika pobytů", "/admin/economy"},
         {"Statistiky prodeje", "/admin/statistics"},
         {"Export POHODA", "/admin/pohoda-export"}
       ]}
    ]
  end

  def active?(path, "/admin"), do: path in ["/admin", "/admin/"]

  def active?(path, "/admin/bookings/calendar") do
    String.starts_with?(path, "/admin/bookings") and not String.ends_with?(path, "/menu")
  end

  def active?(path, "/admin/meal-planner") do
    Enum.any?(
      ["/admin/meal-planner", "/admin/kitchen-shopping", "/admin/recipes", "/admin/ingredients"],
      &within?(path, &1)
    ) or
      (String.starts_with?(path, "/admin/bookings/") and String.ends_with?(path, "/menu"))
  end

  def active?(path, "/admin/orders"),
    do: within?(path, "/admin/orders") or within?(path, "/admin/payments")

  def active?(path, target), do: within?(path, target)

  def secondary_path(path) do
    cond do
      path in ["/admin/bookings", "/admin/bookings/timeline"] ->
        path

      within?(path, "/admin/bookings") ->
        nil

      true ->
        groups()
        |> Enum.flat_map(fn {_, entries} -> entries end)
        |> Enum.map(fn {_, target} -> target end)
        |> Enum.sort_by(&String.length/1, :desc)
        |> Enum.find(&within?(path, &1))
    end
  end

  defp within?(path, target), do: path == target or String.starts_with?(path, target <> "/")
end
