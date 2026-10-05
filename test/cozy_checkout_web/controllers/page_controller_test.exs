defmodule CozyCheckoutWeb.PageControllerTest do
  use CozyCheckoutWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "Select Booking"
    assert response =~ "Quick Order (No Booking)"
  end
end
