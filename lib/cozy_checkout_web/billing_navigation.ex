defmodule CozyCheckoutWeb.BillingNavigation do
  @moduledoc "Shared navigation for accommodation documents and accounting."

  def groups do
    [
      {"Doklady a platby",
       [
         {:documents, "Seznam dokladů", "/admin/billing", "hero-document-text"},
         {:transfers, "Přenosy do ABRA", "/admin/billing/transfers", "hero-arrow-path"},
         {:bank, "Bankovní pohyby", "/admin/billing/bank", "hero-building-library"}
       ]},
      {"Nastavení",
       [
         {:prices, "Ceník ubytování", "/admin/accommodation-prices", "hero-tag"},
         {:settings, "Nastavení fakturace", "/admin/billing/settings",
          "hero-adjustments-horizontal"}
       ]}
    ]
  end

  def section(path) do
    cond do
      path == "/admin/billing" or String.starts_with?(path, "/admin/billing/documents/") ->
        :documents

      String.match?(path, ~r{^/admin/bookings/[^/]+/billing$}) ->
        :documents

      true ->
        groups()
        |> Enum.flat_map(fn {_, entries} -> entries end)
        |> Enum.find_value(fn {section, _, target, _} -> if path == target, do: section end)
    end
  end

  def label(path) do
    cond do
      String.match?(path, ~r{^/admin/bookings/[^/]+/billing$}) ->
        "Fakturace pobytu"

      String.starts_with?(path, "/admin/billing/documents/") ->
        "Detail dokladu"

      true ->
        groups()
        |> Enum.flat_map(fn {_, entries} -> entries end)
        |> Enum.find_value(fn {_, label, target, _} -> if path == target, do: label end)
    end
  end
end
