defmodule CozyCheckoutWeb.KitchenCostPricesLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import CozyCheckout.RecipeFixtures
  alias CozyCheckout.{KitchenCosts, QueryRecorder}
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

  test "initial overview uses at most four queries, including a catalogue with many missing prices",
       %{conn: conn} do
    {{:ok, view, _}, queries} =
      QueryRecorder.record(fn -> live(conn, "/admin/kitchen-costs/prices") end)

    assert has_element?(view, "#ingredient-cost-prices")
    assert length(queries) in 1..4
  end

  test "category and search combine without SQL; opening a history preserves filters and does not reload prices",
       %{conn: conn} do
    selected =
      ingredient_fixture(%{name: "Červená snídaňová test ceny", category: "Test snídaně"})

    same_category =
      ingredient_fixture(%{name: "Jiná snídaňová test ceny", category: "Test snídaně"})

    other_category =
      ingredient_fixture(%{name: "Červená jiná test ceny", category: "Test ostatní"})

    {:ok, _} =
      KitchenCosts.confirm_purchase(%{
        merchant: "Filtr cen",
        purchased_on: Date.utc_today(),
        total_paid: "100",
        lines: [
          %{
            line_number: 1,
            source_name: "Surovina",
            classification: "ingredient",
            ingredient_id: selected.id,
            quantity: "1",
            unit: "kg",
            line_total: "100"
          }
        ]
      })

    {:ok, view, _} = live(conn, "/admin/kitchen-costs/prices")

    {_, queries} =
      QueryRecorder.record(
        fn ->
          view
          |> form("#cost-price-search", search: "cervena", category: "Test snídaně")
          |> render_change()
        end,
        view.pid
      )

    assert queries == []
    assert has_element?(view, "#price-#{selected.id}")
    refute has_element?(view, "#price-#{same_category.id}")
    refute has_element?(view, "#price-#{other_category.id}")

    {_, queries} =
      QueryRecorder.record(
        fn -> view |> element("#price-#{selected.id} a") |> render_click() end,
        view.pid
      )

    assert length(queries) == 2
    refute Enum.any?(queries, &String.contains?(&1, "kitchen_manual_prices"))
    refute Enum.any?(queries, &String.contains?(&1, "kitchen_ingredients"))
    assert has_element?(view, "#ingredient-price-history", selected.name)
    assert has_element?(view, "#cost-price-category option[value='Test snídaně'][selected]")
    assert has_element?(view, "input[name='search'][value='cervena']")
    view |> form("#cost-price-search", search: "", category: "Test snídaně") |> render_change()
    assert has_element?(view, "#price-#{same_category.id}")
    refute has_element?(view, "#price-#{other_category.id}")
    view |> form("#cost-price-search", search: "", category: "") |> render_change()
    assert has_element?(view, "#price-#{other_category.id}")
  end

  test "saving a manual price refreshes the selected row without loading the whole catalogue", %{
    conn: conn
  } do
    ingredient = ingredient_fixture(%{category: "Test ruční ceny"})
    other = ingredient_fixture(%{category: "Test ruční ceny"})

    {:ok, view, _} =
      live(
        conn,
        "/admin/kitchen-costs/prices?#{URI.encode_query(%{ingredient: ingredient.id, category: ingredient.category})}"
      )

    assert has_element?(view, "#price-#{ingredient.id}", "Chybí cena")

    {_, queries} =
      QueryRecorder.record(
        fn ->
          view
          |> form("#manual-price-form",
            price: %{
              valid_from: Date.to_iso8601(Date.utc_today()),
              unit_price: "123.45",
              note: "Test odhadu"
            }
          )
          |> render_submit()
        end,
        view.pid
      )

    # Only the explicit FOR SHARE lookup needed to save the estimate reads an ingredient.
    assert Enum.count(queries, &String.contains?(&1, "FROM \"kitchen_ingredients\"")) == 1
    assert has_element?(view, "#price-#{ingredient.id}", "Ruční odhad")
    assert has_element?(view, "#price-#{ingredient.id}", "123.45 CZK")
    assert has_element?(view, "#price-#{other.id}", "Chybí cena")
    assert has_element?(view, "#cost-price-category option[value='Test ruční ceny'][selected]")
  end
end
