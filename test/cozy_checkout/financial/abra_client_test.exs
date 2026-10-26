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

  test "final invoice reads paginated items through the documented polozkyDokladu relation" do
    cfg = Application.fetch_env!(:cozy_checkout, :abra)

    Req.Test.expect(Client, fn conn ->
      assert conn.request_path == "/c/test/faktura-vydana/236.json"
      Req.Test.json(conn, %{"winstrom" => %{"faktura-vydana" => [%{"id" => 236}]}})
    end)

    for offset <- [0, 100] do
      Req.Test.expect(Client, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/c/test/faktura-vydana/236/polozkyDokladu.json"
        assert Plug.Conn.fetch_query_params(conn).query_params["start"] == to_string(offset)
        rows = if offset == 0, do: Enum.map(1..100, &%{"id" => &1}), else: [%{"id" => 101}]
        Req.Test.json(conn, %{"winstrom" => %{"faktura-vydana-polozka" => rows}})
      end)
    end

    for {relation, key} <- [{"vazebni-doklady", "vazebni-doklad"}, {"vazby", "vazba"}] do
      Req.Test.expect(Client, fn conn ->
        assert conn.request_path == "/c/test/faktura-vydana/236/#{relation}.json"
        Req.Test.json(conn, %{"winstrom" => %{key => []}})
      end)
    end

    assert {:ok, snapshot} = Client.final_invoice_snapshot("236", cfg)
    assert length(snapshot.items) == 101
    assert List.last(snapshot.items)["id"] == 101
    assert snapshot.links == [] and snapshot.amounts == []
  end

  for failed_relation <- ["polozkyDokladu", "vazebni-doklady", "vazby"] do
    test "missing #{failed_relation} is reported explicitly and never interpreted as empty data" do
      failed = unquote(failed_relation)

      Req.Test.stub(Client, fn conn ->
        assert conn.method == "GET"
        relation = Path.basename(conn.request_path, ".json")

        cond do
          relation == "236" ->
            Req.Test.json(conn, %{"winstrom" => %{"faktura-vydana" => [%{"id" => 236}]}})

          relation == failed ->
            Plug.Conn.send_resp(conn, 404, "")

          true ->
            key =
              Map.fetch!(
                %{
                  "polozkyDokladu" => "faktura-vydana-polozka",
                  "vazebni-doklady" => "vazebni-doklad",
                  "vazby" => "vazba"
                },
                relation
              )

            Req.Test.json(conn, %{"winstrom" => %{key => []}})
        end
      end)

      assert {:error, reason} =
               Client.final_invoice_snapshot("236", Application.fetch_env!(:cozy_checkout, :abra))

      assert reason =~ failed
      assert reason =~ "HTTP 404"
    end
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

  test "HTTP 200 with import errors is not considered a successful invoice" do
    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{
        "winstrom" => %{"results" => [%{"id" => 42, "errors" => [%{"message" => "Invalid"}]}]}
      })
    end)

    assert {:error, "Invalid"} = Client.create_invoice(%{})
  end

  test "HTTP 200 without a valid document ID is not considered success" do
    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{"winstrom" => %{"results" => [%{"id" => nil}]}})
    end)

    assert {:error, "unexpected_response"} = Client.create_invoice(%{})
  end
end
