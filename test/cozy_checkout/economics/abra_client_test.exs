defmodule CozyCheckout.Economics.AbraClientTest do
  use ExUnit.Case, async: false
  alias CozyCheckout.Economics.{AbraClient, Config}

  setup do
    previous = Application.get_env(:cozy_checkout, :economics)
    options = Req.default_options()
    Req.default_options(plug: {Req.Test, AbraClient})

    Application.put_env(:cozy_checkout, :economics,
      enabled: true,
      base_url: "https://accounting.test",
      company_id: "reporting",
      username: "reader",
      password: "secret"
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cozy_checkout, :economics, previous),
        else: Application.delete_env(:cozy_checkout, :economics)

      Req.default_options(options)
    end)

    Req.Test.verify_on_exit!()
    :ok
  end

  test "disabled and incomplete configuration never call HTTP or inherit existing ABRA settings" do
    Application.put_env(:cozy_checkout, :economics, enabled: false)
    assert {:error, :disabled} = AbraClient.periods()
    Application.put_env(:cozy_checkout, :economics, enabled: true)
    assert {:error, :invalid_connection} = AbraClient.accounts()
  end

  test "rejects URLs with credentials, queries, fragments, or without HTTPS" do
    for url <- [
          "http://accounting.test",
          "https://user:pass@accounting.test",
          "https://accounting.test?x=1",
          "https://accounting.test/#x"
        ] do
      Application.put_env(:cozy_checkout, :economics, Keyword.put(Config.get(), :base_url, url))
      assert {:error, :invalid_connection} = AbraClient.periods()
    end
  end

  test "movement requests restrict date and posting state, GET only, without personal fields" do
    Req.Test.expect(AbraClient, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.method == "GET"
      assert URI.decode(conn.request_path) =~ "(datUcto >= 2026-09-01 and datUcto <= 2026-09-30)"
      assert conn.query_params["postingState"] == "posted"
      refute conn.query_params["detail"] =~ "nazFirmy"

      assert Plug.Conn.get_req_header(conn, "authorization") == [
               "Basic " <> Base.encode64("reader:secret")
             ]

      Req.Test.json(conn, %{"winstrom" => %{"pohyb-na-uctech" => []}})
    end)

    assert {:ok, []} = AbraClient.movements(~D[2026-09-01], ~D[2026-09-30])
  end

  test "reads all pages, including an empty terminal page" do
    for offset <- [0, 1000] do
      Req.Test.expect(AbraClient, fn conn ->
        assert Plug.Conn.fetch_query_params(conn).query_params["start"] == to_string(offset)
        rows = if offset == 0, do: Enum.map(1..1000, &%{"id" => &1}), else: []
        Req.Test.json(conn, %{"winstrom" => %{"ucet" => rows}})
      end)
    end

    assert {:ok, rows} = AbraClient.accounts()
    assert length(rows) == 1000
  end

  test "a repeated full page fails instead of publishing duplicates" do
    Req.Test.expect(AbraClient, 2, fn conn ->
      Req.Test.json(conn, %{"winstrom" => %{"ucet" => Enum.map(1..1000, &%{"id" => &1})}})
    end)

    assert {:error, :repeated_page} = AbraClient.accounts()
  end

  test "report parameters use the verified fiscal period and historical payment date" do
    Req.Test.expect(AbraClient, fn conn ->
      params = Plug.Conn.fetch_query_params(conn).query_params
      assert params["ucetniObdobi"] == "code:2026"
      assert params["koncovyMesicRok"] == "09/2026"
      assert params["pocetMesicu"] == "3"
      Req.Test.json(conn, %{"winstrom" => %{"obratova-predvaha" => []}})
    end)

    assert {:ok, []} = AbraClient.trial_balance("2026", ~D[2026-09-30], 3)

    Req.Test.expect(AbraClient, fn conn ->
      params = Plug.Conn.fetch_query_params(conn).query_params
      assert params["datum"] == "2026-09-30"
      assert params["dleUcto"] == "true"
      refute params["detail"] =~ "zbyvaUhradit"
      Req.Test.json(conn, %{"winstrom" => %{"saldo-k-datu" => []}})
    end)

    assert {:ok, []} = AbraClient.open_items(~D[2026-09-30])
  end

  for status <- [301, 401, 403, 404, 429, 503] do
    test "HTTP #{status} is returned without redirect or retries" do
      Req.Test.expect(AbraClient, fn conn -> Plug.Conn.send_resp(conn, unquote(status), "") end)
      assert {:error, {:http, unquote(status)}} = AbraClient.periods()
    end
  end

  test "malformed JSON shape and transport failures cannot become empty reports" do
    Req.Test.expect(AbraClient, fn conn -> Req.Test.json(conn, %{"winstrom" => %{}}) end)
    assert {:error, :invalid_response} = AbraClient.periods()
    Req.Test.expect(AbraClient, fn conn -> Req.Test.transport_error(conn, :timeout) end)
    assert {:error, :transport} = AbraClient.periods()
  end
end
