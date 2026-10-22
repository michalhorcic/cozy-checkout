defmodule CozyCheckoutWeb.PageControllerTest do
  use CozyCheckoutWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    document = LazyHTML.from_document(response)

    assert LazyHTML.query(document, "#pos-welcome img[src='/images/rano-nad-udolim.webp']")
           |> Enum.any?()

    assert LazyHTML.query(document, "#pos-new-account") |> LazyHTML.text() |> String.trim() ==
             "Nový účet bez pobytu"
  end
end
