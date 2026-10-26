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

  test "deduction JSON uses a direct array without the XML odpocet wrapper" do
    deduction = %{
      "id" => "ext:deduction:test",
      "doklad" => "100",
      "castkaSnizMen" => "500.00",
      "castkyBezDph" => true,
      "skupPlneni" => "OTHER"
    }

    Req.Test.expect(Client, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/c/test/faktura-vydana.json"
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert Jason.decode!(body) == %{
               "winstrom" => %{
                 "faktura-vydana" => [
                   %{
                     "@create" => "fail",
                     "@update" => "ok",
                     "id" => "236",
                     "odpocty-zaloh" => [deduction]
                   }
                 ]
               }
             }

      Req.Test.json(conn, %{"winstrom" => %{"results" => [%{"id" => 236}]}})
    end)

    assert :ok =
             Client.apply_invoice_deduction(
               "236",
               deduction,
               Application.fetch_env!(:cozy_checkout, :abra)
             )
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

  test "final snapshot reads deduction bindings from source ZDDs and propagates source failures" do
    cfg = Application.fetch_env!(:cozy_checkout, :abra)

    source_binding = %{
      "id" => 900,
      "typVazbyK" => "typVazbyDokl.odpocetZDD",
      "a@ref" => "/v2/c/test/faktura-vydana-polozka/538.json",
      "b@ref" => "/v2/c/test/faktura-vydana/200.json"
    }

    Req.Test.stub(Client, fn conn ->
      case conn.request_path do
        "/c/test/faktura-vydana/236.json" ->
          Req.Test.json(conn, %{"winstrom" => %{"faktura-vydana" => [%{"id" => 236}]}})

        "/c/test/faktura-vydana/236/polozkyDokladu.json" ->
          Req.Test.json(conn, %{"winstrom" => %{"faktura-vydana-polozka" => []}})

        "/c/test/faktura-vydana/236/vazebni-doklady.json" ->
          Req.Test.json(conn, %{"winstrom" => %{"vazebni-doklad" => []}})

        "/c/test/faktura-vydana/236/vazby.json" ->
          Req.Test.json(conn, %{"winstrom" => %{"vazba" => []}})

        "/c/test/faktura-vydana/200/vazby.json" ->
          Req.Test.json(conn, %{"winstrom" => %{"vazba" => [source_binding]}})

        "/c/test/faktura-vydana/201/vazby.json" ->
          Plug.Conn.send_resp(conn, 404, "")
      end
    end)

    assert {:ok, snapshot} = Client.final_invoice_snapshot("236", cfg, ["200"])
    assert snapshot.amounts == []
    assert snapshot.source_bindings == [source_binding]
    assert {:error, reason} = Client.final_invoice_snapshot("236", cfg, ["200", "201"])
    assert reason =~ "zdrojového ZDD ID 201"
    assert reason =~ "HTTP 404"
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
