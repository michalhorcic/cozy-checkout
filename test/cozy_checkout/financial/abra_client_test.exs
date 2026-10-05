defmodule CozyCheckout.AbraClientTest do
  use ExUnit.Case, async: false
  @moduletag :financial
  alias CozyCheckout.Abra.Client

  setup do
    original = Application.fetch_env!(:cozy_checkout, :abra)
    original_options = Req.default_options()
    Req.default_options(plug: {Req.Test, Client})

    Application.put_env(
      :cozy_checkout,
      :abra,
      Keyword.merge(original,
        base_url: "https://accounting.test",
        company_id: "test",
        username: "test-user",
        password: "test-password"
      )
    )

    on_exit(fn ->
      Application.put_env(:cozy_checkout, :abra, original)
      Req.default_options(original_options)
    end)

    Req.Test.verify_on_exit!()
    :ok
  end

  test "POST sends JSON, authentication and parses the returned document ID" do
    payload = %{"winstrom" => %{"faktura-vydana" => [%{"id" => "ext:cozy-checkout:order"}]}}

    Req.Test.expect(Client, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/c/test/faktura-vydana.json"

      assert Plug.Conn.get_req_header(conn, "authorization") == [
               "Basic " <> Base.encode64("test-user:test-password")
             ]

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body) == payload

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"winstrom" => %{"results" => [%{"id" => 42}]}})
    end)

    assert {:ok, "42"} = Client.create_invoice(payload)
  end

  for {status, body, expected} <- [
        {422, %{"winstrom" => %{"results" => [%{"errors" => [%{"message" => "Bad amount"}]}]}},
         "Bad amount"},
        {503, %{}, "HTTP 503"},
        {200, %{}, "unexpected_response"}
      ] do
    test "HTTP #{status} with body #{inspect(body)} returns an error without automatic retry" do
      Req.Test.expect(Client, fn conn ->
        conn
        |> Plug.Conn.put_status(unquote(status))
        |> Req.Test.json(unquote(Macro.escape(body)))
      end)

      assert {:error, unquote(expected)} = Client.create_invoice(%{})
    end
  end

  test "a transport timeout returns an error without automatic retry" do
    Req.Test.expect(Client, fn conn -> Req.Test.transport_error(conn, :timeout) end)
    assert {:error, reason} = Client.create_invoice(%{})
    assert is_binary(reason)
  end

  @tag :known_bug
  test "HTTP 200 with import errors is not considered a successful invoice" do
    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{
        "winstrom" => %{"results" => [%{"id" => 42, "errors" => [%{"message" => "Invalid"}]}]}
      })
    end)

    assert {:error, _} = Client.create_invoice(%{})
  end

  @tag :known_bug
  test "HTTP 200 without a valid document ID is not considered success" do
    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{"winstrom" => %{"results" => [%{"id" => nil}]}})
    end)

    assert {:error, _} = Client.create_invoice(%{})
  end
end
