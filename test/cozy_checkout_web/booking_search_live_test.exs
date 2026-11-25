defmodule CozyCheckoutWeb.BookingSearchLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CozyCheckout.MenuFixtures
  alias CozyCheckoutWeb.AdminAuth

  setup %{conn: conn} do
    previous = Application.get_env(:cozy_checkout, :admin_pin_hash)
    Application.put_env(:cozy_checkout, :admin_pin_hash, AdminAuth.hash_pin("482731"))

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cozy_checkout, :admin_pin_hash, previous),
        else: Application.delete_env(:cozy_checkout, :admin_pin_hash)
    end)

    conn =
      Plug.Test.init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})

    {:ok, conn: conn}
  end

  for show_all <- [false, true] do
    @show_all show_all
    test "search and filters respect show_all=#{show_all}", %{conn: conn} do
      today = Date.utc_today()

      bookings =
        for offset <- [-2, 0, 2] do
          menu_booking_fixture(%{
            check_in_date: Date.add(today, offset - 1),
            check_out_date: Date.add(today, offset),
            status: "upcoming"
          })
        end

      [past, current, future] = bookings
      scope = if @show_all, do: %{"show_all" => "true"}, else: %{}

      for filters <- [
            %{},
            %{"guest_search" => "Skupina"},
            %{"guest_search" => ""},
            %{"invoice_state" => "no_document"},
            %{
              "filters" => %{
                "0" => %{"field" => "status", "op" => "==", "value" => "upcoming"}
              }
            }
          ] do
        query = Plug.Conn.Query.encode(Map.merge(scope, filters))
        {:ok, view, _} = live(conn, "/admin/bookings?" <> query)

        assert has_element?(view, "#booking-row-#{current.id}")
        assert has_element?(view, "#booking-row-#{future.id}")
        assert has_element?(view, "#booking-row-#{past.id}") == @show_all

        view
        |> form("#bookings-filter", guest_search: "Skupina")
        |> render_change()

        assert has_element?(view, "#booking-row-#{current.id}")
        assert has_element?(view, "#booking-row-#{future.id}")
        assert has_element?(view, "#booking-row-#{past.id}") == @show_all
        params = Plug.Conn.Query.decode(URI.parse(assert_patch(view)).query || "")
        assert params["show_all"] == "true" == @show_all
      end
    end
  end
end
