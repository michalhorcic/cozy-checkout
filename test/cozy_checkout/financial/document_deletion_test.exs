defmodule CozyCheckout.DocumentDeletionTest do
  use CozyCheckout.DataCase, async: false
  @moduletag :financial
  import CozyCheckout.BillingFixtures
  alias CozyCheckout.{Billing, Repo}

  test "hides each invoice kind, retains audit data and allows a new final" do
    %{booking: booking} = billing_fixture()

    for kind <- ["advance", "final"] do
      doc =
        issue_without_abra!(
          booking,
          kind,
          if(kind == "advance", do: %{"percent" => "50"}, else: %{})
        )

      assert {:ok, deleted} = Billing.delete_document(doc.id)
      assert deleted.deleted_at
      assert Repo.get!(Billing.Document, doc.id).number == doc.number
      refute Enum.any?(Billing.list_documents(), &(&1.id == doc.id))
      assert_raise Ecto.NoResultsError, fn -> Billing.get_document!(doc.id) end
    end

    refute Billing.final_document(booking.id)
    assert issue_without_abra!(booking, "final").id
  end

  test "even a partial or unassigned payment blocks deletion" do
    %{booking: booking} = billing_fixture()
    doc = issue_without_abra!(booking, "advance", %{"percent" => "50"})
    receipt!(booking, "1")
    assert {:error, reason} = Billing.delete_document(doc.id)
    assert reason =~ "platbu"
    assert is_nil(Billing.get_document!(doc.id).deleted_at)
  end

  test "a final with deductions cannot be deleted" do
    %{booking: booking} = billing_fixture()
    receipt!(booking, "100")
    doc = issue_without_abra!(booking, "final")
    assert {:error, _} = Billing.delete_document(doc.id)
  end

  test "ABRA cancellation verifies the remote result and is idempotent" do
    alias CozyCheckout.Abra.{Client, InvoiceCancellation}

    cfg = [
      base_url: "https://accounting.test",
      company_id: "test",
      username: "test",
      password: "test"
    ]

    export = %{external_id: "ext:cozy:test", remote_id: "42"}
    doc = %{number: "TEST202600001", variable_symbol: "1202600001"}

    remote = %{
      "id" => 42,
      "kod" => doc.number,
      "varSym" => doc.variable_symbol,
      "juhSum" => "0",
      "storno" => false
    }

    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{"winstrom" => %{"faktura-vydana" => [remote]}})
    end)

    Req.Test.expect(Client, fn conn ->
      assert conn.method == "POST"
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert get_in(Jason.decode!(body), ["winstrom", "faktura-vydana", Access.at(0), "storno"]) ==
               true

      Req.Test.json(conn, %{"winstrom" => %{"results" => [%{"id" => 42}]}})
    end)

    cancelled = Map.put(remote, "storno", true)

    Req.Test.expect(Client, 2, fn conn ->
      Req.Test.json(conn, %{"winstrom" => %{"faktura-vydana" => [cancelled]}})
    end)

    assert :ok = InvoiceCancellation.cancel(export, doc, cfg)
    assert :ok = InvoiceCancellation.cancel(export, doc, cfg)
    Req.Test.verify!()
  end

  test "ABRA payment blocks cancellation before any write" do
    alias CozyCheckout.Abra.{Client, InvoiceCancellation}

    cfg = [
      base_url: "https://accounting.test",
      company_id: "test",
      username: "test",
      password: "test"
    ]

    doc = %{number: "TEST", variable_symbol: "123"}
    remote = %{"id" => 42, "kod" => "TEST", "varSym" => "123", "juhSum" => "1", "storno" => false}

    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{"winstrom" => %{"faktura-vydana" => [remote]}})
    end)

    assert {:error, reason} =
             InvoiceCancellation.cancel(%{external_id: "ext:test", remote_id: "42"}, doc, cfg)

    assert reason =~ "úhradu"
    Req.Test.verify!()
  end
end
