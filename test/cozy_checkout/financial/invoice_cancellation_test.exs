defmodule CozyCheckout.InvoiceCancellationTest do
  use ExUnit.Case, async: false
  @moduletag :financial
  alias CozyCheckout.Abra.{Client, InvoiceCancellation}

  setup do
    Req.Test.verify_on_exit!()

    cfg = [
      base_url: "https://accounting.test",
      company_id: "test",
      username: "user",
      password: "password"
    ]

    export = %{external_id: "ext:test", remote_id: "42"}
    doc = %{number: "TEST42", variable_symbol: "123"}

    remote = %{
      "id" => 42,
      "kod" => doc.number,
      "varSym" => doc.variable_symbol,
      "juhSum" => "0",
      "storno" => false,
      "zamekK" => "zamek.zamceno"
    }

    %{cfg: cfg, export: export, doc: doc, remote: remote}
  end

  test "uses the storno action and includes ABRA warnings when read-back is not cancelled", ctx do
    expect_read(ctx.remote)

    Req.Test.expect(Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert Jason.decode!(body) == %{
               "winstrom" => %{"faktura-vydana" => [%{"id" => "ext:test", "@action" => "storno"}]}
             }

      Req.Test.json(conn, %{
        "winstrom" => %{
          "success" => true,
          "results" => [
            %{"id" => 42, "warnings" => [%{"code" => "locked", "message" => "Doklad je uzamčen"}]}
          ]
        }
      })
    end)

    expect_read(ctx.remote)
    assert {:error, reason} = InvoiceCancellation.cancel(ctx.export, ctx.doc, ctx.cfg)
    assert reason =~ "HTTP 200"
    assert reason =~ "storno=false"
    assert reason =~ "zamek.zamceno"
    assert reason =~ "locked: Doklad je uzamčen"
    assert reason =~ "Místní faktura nebyla smazána"
  end

  test "says explicitly when ABRA gives no explanation", ctx do
    expect_read(ctx.remote)

    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{"winstrom" => %{"results" => [%{"id" => 42}]}})
    end)

    expect_read(ctx.remote)
    assert {:error, reason} = InvoiceCancellation.cancel(ctx.export, ctx.doc, ctx.cfg)
    assert reason =~ "ABRA neuvedla důvod"
  end

  test "reports all API error messages even with HTTP 200, without another read", ctx do
    expect_read(ctx.remote)

    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{
        "winstrom" => %{
          "success" => false,
          "results" => [
            %{
              "id" => 42,
              "errors" => [
                %{"code" => "locked", "message" => "Doklad je uzamčen"},
                %{"message" => "Uzavřené období"}
              ]
            }
          ]
        }
      })
    end)

    assert {:error, reason} = InvoiceCancellation.cancel(ctx.export, ctx.doc, ctx.cfg)
    assert reason =~ "HTTP 200"
    assert reason =~ "locked: Doklad je uzamčen"
    assert reason =~ "Uzavřené období"
  end

  test "reports an HTTP rejection and its top-level error", ctx do
    expect_read(ctx.remote)

    Req.Test.expect(Client, fn conn ->
      conn
      |> Plug.Conn.put_status(403)
      |> Req.Test.json(%{"winstrom" => %{"errors" => [%{"message" => "Chybí právo na storno"}]}})
    end)

    assert {:error, reason} = InvoiceCancellation.cancel(ctx.export, ctx.doc, ctx.cfg)
    assert reason =~ "HTTP 403"
    assert reason =~ "Chybí právo na storno"
  end

  test "a lost action response can be retried without sending a second storno", ctx do
    expect_read(ctx.remote)
    Req.Test.expect(Client, &Req.Test.transport_error(&1, :timeout))
    assert {:error, reason} = InvoiceCancellation.cancel(ctx.export, ctx.doc, ctx.cfg)
    assert reason =~ "Volání storna ABRA selhalo"
    expect_read(Map.put(ctx.remote, "storno", true))
    assert :ok = InvoiceCancellation.cancel(ctx.export, ctx.doc, ctx.cfg)
  end

  defp expect_read(remote) do
    Req.Test.expect(Client, fn conn ->
      assert conn.method == "GET"
      Req.Test.json(conn, %{"winstrom" => %{"faktura-vydana" => [remote]}})
    end)
  end
end
