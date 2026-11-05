defmodule CozyCheckout.IncomingDocuments.ImportTransportTest do
  use ExUnit.Case, async: false
  alias CozyCheckout.IncomingDocuments.{Client, Document, XML}

  setup do
    previous = Req.default_options()
    Req.default_options(plug: {Req.Test, __MODULE__})
    Req.Test.verify_on_exit!()
    on_exit(fn -> Req.default_options(previous) end)
    :ok
  end

  defp config,
    do: [
      base_url: "https://accounting.test",
      company_id: "pilot",
      username: "test",
      password: "password"
    ]

  defp doc do
    %Document{
      agenda: "faktura-prijata",
      external_id: "ext:cozy-incoming:test",
      base_url: "https://accounting.test",
      company_id: "pilot"
    }
  end

  defp response(conn),
    do: Req.Test.json(conn, %{"winstrom" => %{"success" => true, "results" => [%{"id" => "42"}]}})

  test "incoming imports use the same JSON request convention as working accommodation invoices" do
    cfg = config()

    invoice = %{
      "winstrom" => %{
        "faktura-vydana" => [
          %{
            "id" => "ext:cozy-checkout:accommodation:test",
            "@create" => "ok",
            "@update" => "fail",
            "ucetni" => false
          }
        ]
      }
    }

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/c/pilot/faktura-vydana.json"
      assert Plug.Conn.get_req_header(conn, "content-type") == ["application/json"]
      assert Plug.Conn.get_req_header(conn, "accept") == ["application/json"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body) == invoice
      response(conn)
    end)

    assert {:ok, "42"} = CozyCheckout.Abra.Client.create_invoice(invoice, cfg)

    doc = doc()

    xml =
      XML.render(
        %{
          "bezPolozek" => "true",
          "ucetni" => "true",
          "cisDosle" => "R42",
          "sumOsv" => "99.00",
          "sumCelkem" => "99.00",
          "datUcto" => ""
        },
        doc.agenda,
        doc.external_id
      )

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/c/pilot/faktura-prijata.json"
      assert Plug.Conn.get_req_header(conn, "content-type") == ["application/json"]
      assert Plug.Conn.get_req_header(conn, "accept") == ["application/json"]

      assert Plug.Conn.get_req_header(conn, "authorization") == [
               "Basic " <> Base.encode64("test:password")
             ]

      refute Map.has_key?(Plug.Conn.fetch_query_params(conn).query_params, "dry-run")
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert %{"winstrom" => %{"faktura-prijata" => [record]}} = Jason.decode!(body)
      assert record["@create"] == "ok"
      assert record["@update"] == "fail"
      assert record["id"] == doc.external_id
      assert record["sumCelkem"] == "99.00"
      assert record["bezPolozek"] === true
      refute Map.has_key?(record, "datUcto")
      response(conn)
    end)

    assert {:ok, result} = Client.import(doc, xml, false, cfg)
    assert result["request"]["content_type"] == "application/json"
    assert result["request"]["source_xml_hash"] == CozyCheckout.IncomingDocuments.digest(xml)
  end

  test "dry-run and real import send identical JSON content and differ only in the dry-run parameter" do
    doc = doc()

    xml =
      XML.render(
        %{"bezPolozek" => "true", "ucetni" => "true", "sumCelkem" => "99.00"},
        doc.agenda,
        doc.external_id
      )

    for dry? <- [true, false] do
      Req.Test.expect(__MODULE__, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["dry-run"] == if(dry?, do: "true", else: nil)
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(self(), {:payload, body})
        response(conn)
      end)

      assert {:ok, _} = Client.import(doc, xml, dry?, config())
    end

    assert_receive {:payload, test_body}
    assert_receive {:payload, real_body}
    assert test_body == real_body
  end

  test "invalid XML never triggers an HTTP request" do
    assert {:rejected, _, _} = Client.import(doc(), "<html>not XML</html>", false, config())
  end
end
