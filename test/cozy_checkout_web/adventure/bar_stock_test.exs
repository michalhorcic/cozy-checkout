defmodule CozyCheckoutWeb.AdventureBarStockLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias CozyCheckout.{Adventure, Repo}
  alias CozyCheckout.Adventure.XpTransaction
  alias CozyCheckoutWeb.AdminAuth

  setup %{conn: conn} do
    Repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ", [],
      sandbox_subtransaction: false
    )

    previous = Application.get_env(:cozy_checkout, :adventure_enabled, false)
    pin = Application.get_env(:cozy_checkout, :admin_pin_hash)
    Application.put_env(:cozy_checkout, :adventure_enabled, true)
    Application.put_env(:cozy_checkout, :admin_pin_hash, AdminAuth.hash_pin("482731"))

    on_exit(fn ->
      Application.put_env(:cozy_checkout, :adventure_enabled, previous)

      if pin,
        do: Application.put_env(:cozy_checkout, :admin_pin_hash, pin),
        else: Application.delete_env(:cozy_checkout, :admin_pin_hash)
    end)

    conn = init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})
    {:ok, conn: conn}
  end

  test "bar owns its refresh and keeps a snapshot across parent renders", %{conn: conn} do
    {:ok, _} = Adventure.initialize()

    product =
      Repo.insert!(
        CozyCheckout.Catalog.Product.changeset(%CozyCheckout.Catalog.Product{}, %{
          name: "Bar missing evidence",
          unit: "pcs",
          track_bar_stock: true,
          bar_stock_threshold: 10
        })
      )

    counter = :atomics.new(1, [])
    handler = {__MODULE__, make_ref()}
    :telemetry.attach(handler, [:cozy_checkout, :repo, :query], &__MODULE__.bar_query/4, counter)
    on_exit(fn -> :telemetry.detach(handler) end)
    assert get(conn, "/admin/adventure").status == 200
    assert :atomics.get(counter, 1) == 0
    {:ok, view, _} = live(conn, "/admin/adventure")
    assert has_element?(view, "#adventure-bar-stock", "Chybí evidence")
    assert :atomics.get(counter, 1) == 1
    view |> element("#adventure-area-bar") |> render_click()
    assert has_element?(view, "#adventure-bar-stock", "Bar missing evidence")

    Repo.insert!(
      CozyCheckout.Inventory.BarStockMovement.changeset(
        %CozyCheckout.Inventory.BarStockMovement{},
        %{product_id: product.id, quantity: 5, movement_type: "restock"}
      )
    )

    view |> element("#adventure-operation-refresh") |> render_click()
    assert has_element?(view, "#adventure-bar-stock", "Chybí evidence")
    assert :atomics.get(counter, 1) == 1
    view |> element("#adventure-bar-refresh") |> render_click()
    assert has_element?(view, "#adventure-bar-stock ul li span", "5 pcs")
    refute has_element?(view, "#adventure-bar-stock", "Chybí evidence")
    assert has_element?(view, "#adventure-bar-stock a[href='/admin/bar-stock']")
    assert :atomics.get(counter, 1) == 2
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "failed refresh retains clearly marked old evidence and stale timestamp" do
    loaded_at = ~U[2026-11-12 10:00:00Z]

    snapshot = %{
      loaded_at: loaded_at,
      tracked_count: 1,
      products: [
        %{
          name: "Last evidence",
          stock: Decimal.new(2),
          unit: "pcs",
          threshold: Decimal.new(3),
          status: :low_stock
        }
      ]
    }

    html =
      render_component(CozyCheckoutWeb.AdventureLive.BarStockComponent,
        id: "adventure-bar-stock",
        snapshot: snapshot,
        state: :error,
        started: true,
        now: DateTime.add(loaded_at, 900)
      )

    assert html =~ "Bar se teď neozývá"
    assert html =~ "Last evidence"
    assert html =~ "Starší přehled"
    assert html =~ "Před 15 min"
    assert html =~ "2026-11-12T10:00:00Z"
    document = LazyHTML.from_fragment(html)
    text = LazyHTML.text(document)
    refute text =~ "2026-11-12"
    refute text =~ "UTC"
    assert Enum.empty?(LazyHTML.query(document, "details"))

    empty =
      render_component(CozyCheckoutWeb.AdventureLive.BarStockComponent,
        id: "adventure-bar-stock",
        state: :error,
        started: true
      )

    assert empty =~ "Zatím bez přehledu"
    refute empty =~ "Sledujeme"
  end

  def bar_query(_, _, metadata, counter) do
    if String.contains?(metadata.query, "FROM products p"), do: :atomics.add(counter, 1, 1)
  end
end
