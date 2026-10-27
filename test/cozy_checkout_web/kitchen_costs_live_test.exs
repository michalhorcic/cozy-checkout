defmodule CozyCheckoutWeb.KitchenCostsLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import CozyCheckout.RecipeFixtures
  import CozyCheckout.ShoppingFixtures
  alias CozyCheckout.{KitchenCosts, Repo}
  alias CozyCheckout.KitchenCosts.{Purchase, Reports}
  alias CozyCheckoutWeb.AdminAuth

  setup %{conn: conn} do
    previous = Application.get_env(:cozy_checkout, :admin_pin_hash)
    Application.put_env(:cozy_checkout, :admin_pin_hash, AdminAuth.hash_pin("482731"))

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cozy_checkout, :admin_pin_hash, previous),
        else: Application.delete_env(:cozy_checkout, :admin_pin_hash)
    end)

    {:ok,
     conn:
       Plug.Test.init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})}
  end

  defp receipt(ingredient) do
    data =
      Application.app_dir(:cozy_checkout, "priv/kitchen_costs/receipt-v1.example.json")
      |> File.read!()
      |> Jason.decode!()

    [item | _] = data["items"]

    data
    |> Map.put("import_id", Ecto.UUID.generate())
    |> Map.put(
      "receipt",
      Map.merge(data["receipt"], %{
        "total_paid" => "59.80",
        "rounding" => "0",
        "shared_discount" => "0"
      })
    )
    |> Map.put("items", [
      Map.merge(item, %{
        "proposed_ingredient_id" => ingredient.id,
        "proposed_ingredient_name" => ingredient.name
      })
    ])
  end

  test "catalog and contract downloads and every kitchen-cost route require the admin PIN", %{
    conn: conn
  } do
    unauthenticated = Phoenix.ConnTest.build_conn()

    for path <- [
          "/admin/kitchen-costs",
          "/admin/kitchen-costs/new",
          "/admin/kitchen-costs/prices",
          "/admin/kitchen-costs/reports"
        ] do
      assert {:error, {:redirect, %{to: "/admin/login"}}} = live(unauthenticated, path)
    end

    for path <- ["/admin/kitchen-costs/catalog.json", "/admin/kitchen-costs/contract/CHATGPT.md"] do
      assert redirected_to(get(unauthenticated, path)) == "/admin/login"
    end

    catalog = get(conn, "/admin/kitchen-costs/catalog.json")

    assert %{"schema_version" => 1, "ingredients" => [_ | _]} =
             Jason.decode!(response(catalog, 200))

    assert get_resp_header(catalog, "cache-control") == ["private, no-store"]

    assert get(conn, "/admin/kitchen-costs/contract/receipt-v1.schema.json")
           |> response(200)
           |> Jason.decode!()
           |> Map.has_key?("$schema")
  end

  test "receipt preview, explicit confirmation, prices, recipe costs and immutable report form a complete flow",
       %{conn: conn} do
    {ingredient, recipe} = shopping_recipe()
    {booking, _} = shopping_booking(recipe)
    data = receipt(ingredient)
    {:ok, view, _} = live(conn, "/admin/kitchen-costs/new")
    view |> form("#kitchen-import-form", import: %{json: Jason.encode!(data)}) |> render_submit()
    assert has_element?(view, "#purchase-line-0", "Návrh JSON")
    view |> form("#kitchen-purchase-form") |> render_submit()
    assert has_element?(view, "#kitchen-cost-error", "Potvrďte přiřazení")

    result =
      view
      |> form("#kitchen-purchase-form",
        purchase: %{lines: %{"0" => %{confirmed_ingredient_id: ingredient.id, remember: "true"}}}
      )
      |> render_submit()

    [purchase] = KitchenCosts.list_purchases()

    assert KitchenCosts.mapping_for(data["receipt"]["merchant"], hd(data["items"])["source_name"]).ingredient_id ==
             ingredient.id

    {:ok, detail, _} = follow_redirect(result, conn, "/admin/kitchen-costs/#{purchase.id}")
    assert has_element?(detail, "#replace-purchase")
    assert purchase.original_json == data

    {:ok, prices, _} = live(conn, "/admin/kitchen-costs/prices?ingredient=#{ingredient.id}")
    assert has_element?(prices, "#ingredient-price-history", "Rajský protlak")
    {:ok, recipe_view, _} = live(conn, "/admin/recipes/#{recipe.id}")
    assert has_element?(recipe_view, "#recipe-portion-costs", "Dospělá porce")

    path = "/admin/kitchen-costs/reports?from=2027-01-08&to=2027-01-10&booking=#{booking.id}"
    {:ok, report_view, _} = live(conn, path)
    refute has_element?(report_view, "#incomplete-cost-report")
    result = report_view |> element("#save-cost-report") |> render_click()
    [saved] = Reports.list()

    {:ok, snapshot_view, _} =
      follow_redirect(result, conn, "/admin/kitchen-costs/reports/#{saved.id}")

    assert has_element?(snapshot_view, "#saved-cost-report")
    refute has_element?(snapshot_view, "#save-cost-report")
    assert saved.snapshot["portions"] == 75

    {:ok, repeat, _} = live(conn, "/admin/kitchen-costs/new")

    repeat
    |> form("#kitchen-import-form", import: %{json: Jason.encode!(data)})
    |> render_submit()

    repeat
    |> form("#kitchen-purchase-form",
      purchase: %{lines: %{"0" => %{confirmed_ingredient_id: ingredient.id}}}
    )
    |> render_submit()

    assert Repo.aggregate(Purchase, :count) == 1
  end

  test "a dictionary conflict displays both proposals and is not silently overwritten", %{
    conn: conn
  } do
    proposed = ingredient_fixture()
    known = ingredient_fixture()
    data = receipt(proposed)
    merchant = data["receipt"]["merchant"]
    name = hd(data["items"])["source_name"]
    {:ok, _} = KitchenCosts.set_mapping(merchant, name, known.id, nil)
    {:ok, view, _} = live(conn, "/admin/kitchen-costs/new")
    view |> form("#kitchen-import-form", import: %{json: Jason.encode!(data)}) |> render_submit()
    assert has_element?(view, "#purchase-line-0", "Konflikt návrhu se slovníkem")

    assert has_element?(
             view,
             "#purchase-line-0_ingredient_id option[value='#{known.id}'][selected]"
           )

    view
    |> form("#kitchen-purchase-form",
      purchase: %{lines: %{"0" => %{confirmed_ingredient_id: known.id}}}
    )
    |> render_submit()

    assert KitchenCosts.mapping_for(merchant, name).ingredient_id == known.id
    assert hd(hd(KitchenCosts.list_purchases()).lines).ingredient_id == known.id
  end

  test "manual entry can add and remove rows and save non-food or unresolved purchases", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/admin/kitchen-costs/new")
    view |> element("#add-purchase-line") |> render_click()
    assert has_element?(view, "#purchase-line-1")
    view |> element("button[phx-click='remove_line'][phx-value-index='1']") |> render_click()
    refute has_element?(view, "#purchase-line-1")

    view
    |> form("#kitchen-purchase-form",
      purchase: %{
        merchant: "Ruční nákup",
        purchased_on: "2026-10-27",
        total_paid: "50",
        rounding: "0",
        lines: %{
          "0" => %{
            source_name: "Drogerie",
            classification: "other",
            quantity: "1",
            unit: "ks",
            line_total: "50"
          }
        }
      }
    )
    |> render_submit()

    [purchase] = KitchenCosts.list_purchases()
    assert hd(purchase.lines).classification == "other"
    {:ok, replacement, _} = live(conn, "/admin/kitchen-costs/#{purchase.id}/edit")

    replacement
    |> form("#kitchen-purchase-form",
      purchase: %{total_paid: "60", lines: %{"0" => %{line_total: "60"}}}
    )
    |> render_submit()

    assert length(KitchenCosts.list_purchases()) == 2
    assert Decimal.equal?(KitchenCosts.get_purchase!(purchase.id).total_paid, "50")
  end

  test "missing prices and invalid report ranges have visible incomplete or error states", %{
    conn: conn
  } do
    {_, recipe} = shopping_recipe()
    {booking, _} = shopping_booking(recipe)

    {:ok, view, _} =
      live(
        conn,
        "/admin/kitchen-costs/reports?from=2027-01-08&to=2027-01-10&booking=#{booking.id}"
      )

    assert has_element?(view, "#incomplete-cost-report", "Neúplná kalkulace")
    assert has_element?(view, "#cost-report-warnings", "Chybí cena")

    view
    |> form("#cost-report-range", range: %{from: "2027-01-10", to: "2027-01-08"})
    |> render_submit()

    assert has_element?(view, "#cost-report-error")
    refute has_element?(view, "#save-cost-report")
  end

  test "duplicate acknowledgement survives form validation", %{conn: conn} do
    attrs = %{
      merchant: "Stejný nákup",
      purchased_on: ~D[2026-10-27],
      total_paid: "50",
      lines: [
        %{
          line_number: 1,
          source_name: "Jiné zboží",
          classification: "other",
          quantity: "1",
          unit: "ks",
          line_total: "50"
        }
      ]
    }

    assert {:ok, _} = KitchenCosts.confirm_purchase(attrs)
    {:ok, view, _} = live(conn, "/admin/kitchen-costs/new")

    params = %{
      merchant: "Stejný nákup",
      purchased_on: "2026-10-27",
      total_paid: "50",
      rounding: "0",
      lines: %{
        "0" => %{
          source_name: "Jiné zboží",
          classification: "other",
          quantity: "1",
          unit: "ks",
          line_total: "50"
        }
      }
    }

    view |> form("#kitchen-purchase-form", purchase: params) |> render_submit()
    assert has_element?(view, "#kitchen-cost-error", "Možná duplicita")

    view
    |> form("#kitchen-purchase-form", purchase: Map.put(params, :allow_duplicate, "true"))
    |> render_change()

    assert has_element?(view, "input[name='purchase[allow_duplicate]'][type='checkbox'][checked]")
    view |> form("#kitchen-purchase-form") |> render_submit()
    assert Repo.aggregate(Purchase, :count) == 2
  end
end
