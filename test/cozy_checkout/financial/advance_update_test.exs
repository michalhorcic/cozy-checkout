defmodule CozyCheckout.AdvanceUpdateTest do
  use CozyCheckout.DataCase, async: false
  @moduletag :financial
  import CozyCheckout.BillingFixtures
  alias CozyCheckout.Billing
  alias CozyCheckout.Abra.{Accommodation, AccommodationExport, AdvanceBuilder, Client}

  setup do
    previous = Application.get_env(:cozy_checkout, :abra_accommodation)

    Application.put_env(:cozy_checkout, :abra_accommodation,
      enabled: true,
      enabled_from: ~U[2020-01-01 00:00:00Z],
      base_url: "https://accounting.test",
      company_id: "test-accommodation",
      username: "test-user",
      password: "test-password",
      advance_type_code: "ZÁLOHA",
      bank_account_code: "TEST-UCET"
    )

    on_exit(fn -> Application.put_env(:cozy_checkout, :abra_accommodation, previous) end)
    Req.Test.verify_on_exit!()
    fixture = billing_fixture()
    doc = issue_without_abra!(fixture.booking, "advance", %{"percent" => "50"})
    Map.put(fixture, :document, doc)
  end

  test "refreshes a percentage advance and PDF without changing its identity or creating documents",
       ctx do
    doc = ctx.document
    Repo.update!(Ecto.Changeset.change(doc, pdf: "old PDF", pdf_sha256: "old hash"))
    add_fee(ctx.booking)
    assert Billing.get_document!(doc.id).total == doc.total
    updated = update!(doc)
    assert updated.id == doc.id
    assert updated.number == doc.number
    assert updated.variable_symbol == doc.variable_symbol
    assert updated.request_id == doc.request_id
    assert updated.issued_on == doc.issued_on
    assert updated.due_on == doc.due_on
    assert updated.snapshot["supplier"] == doc.snapshot["supplier"]
    assert Decimal.equal?(updated.total, "3000")
    assert Decimal.equal?(updated.snapshot["advance_calculation"]["stay_total"], "6000")
    assert Enum.any?(updated.lines, &(&1["tax_mode"] == "outside"))
    assert updated.pdf == nil
    assert updated.pdf_sha256 == nil
    assert Repo.aggregate(Billing.Document, :count) == 1
  end

  test "keeps an explicit advance amount and allows entering a new amount", ctx do
    doc = issue_without_abra!(ctx.booking, "advance", %{"amount" => "1000"})
    add_fee(ctx.booking)
    assert Decimal.equal?(update!(doc).total, "1000")
    assert Decimal.equal?(update!(doc, %{"amount" => "1500"}).total, "1500")
    assert Decimal.equal?(update!(doc, %{"percent" => "100"}).total, "6000")
  end

  test "rejects a stale preview and a forged request to update a final invoice", ctx do
    {:ok, preview} = Billing.preview_advance_update(ctx.document.id)
    add_fee(ctx.booking)

    assert {:error, message} =
             Billing.update_advance(ctx.document.id, %{"preview_token" => preview.token})

    assert message =~ "Podklady se změnily"
    final = issue_without_abra!(ctx.booking, "final")
    assert {:error, _} = Billing.preview_advance_update(final.id)
    assert {:error, _} = Billing.update_advance(final.id, %{})
    assert {:error, _} = Billing.preview_advance_update(ctx.document.id)
  end

  test "rejects an advance already queued for email or a payer with a recorded payment", ctx do
    doc = ctx.document

    {:ok, _} =
      Billing.enqueue_email(
        doc.id,
        %{
          "consent" => "true",
          "recipient" => "guest@example.com",
          "subject" => "Záloha",
          "body" => "V příloze."
        },
        Ecto.UUID.generate()
      )

    assert {:error, message} = Billing.preview_advance_update(doc.id)
    assert message =~ "odeslání"

    other = issue_without_abra!(ctx.booking, "advance")
    receipt!(ctx.booking, "100")
    assert {:error, message} = Billing.preview_advance_update(other.id)
    assert message =~ "platbu"
  end

  test "requires the first export to finish and leaves updates for an explicit transfer", ctx do
    {:ok, export} = Accommodation.enqueue(ctx.document.id)
    assert {:error, message} = Billing.preview_advance_update(ctx.document.id)
    assert message =~ "Probíhá přenos"
    mark_synced(export)
    add_fee(ctx.booking)
    update!(ctx.document)
    assert Accommodation.get_export(ctx.document.id).state == "outdated"
    Req.Test.stub(Client, fn _ -> flunk("No HTTP before explicit enqueue") end)
    assert :ok = Accommodation.sync(export.id)
    assert Accommodation.get_export(ctx.document.id).state == "outdated"
  end

  test "replaces the same remote invoice including its outside-VAT fee and recovers a lost response",
       ctx do
    old = ctx.document
    {:ok, export} = Accommodation.enqueue(old.id)
    mark_synced(export)
    add_fee(ctx.booking)
    doc = update!(old)
    {:ok, update} = Accommodation.enqueue(doc.id)
    [invoice] = update.payload["winstrom"]["faktura-vydana"]
    assert invoice["@create"] == "fail"
    assert invoice["@update"] == "ok"
    assert invoice["polozkyFaktury@removeAll"] == "true"
    assert invoice["id"] == export.external_id
    assert invoice["kod"] == old.number
    assert invoice["varSym"] == old.variable_symbol
    assert length(invoice["polozkyFaktury"]) == 2

    assert Enum.all?(
             invoice["polozkyFaktury"],
             &String.starts_with?(&1["id"], "ext:cozy-checkout:advance-item:")
           )

    {:ok, old_payload} = AdvanceBuilder.build(old, Accommodation.config())
    [old_invoice] = old_payload["winstrom"]["faktura-vydana"]
    expect_snapshot(old_invoice)

    Req.Test.expect(Client, fn conn ->
      assert conn.method == "POST"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body) == update.payload
      Req.Test.transport_error(conn, :timeout)
    end)

    assert {:error, _} = Accommodation.sync(update.id)
    expect_snapshot(invoice)
    assert :ok = Accommodation.sync(update.id)
    assert :ok = Accommodation.sync(update.id)
    assert %{state: "synced", remote_id: "42"} = Accommodation.get_export(doc.id)
    assert Repo.aggregate(AccommodationExport, :count) == 1
    assert Repo.aggregate(Billing.Document, :count) == 1
  end

  test "does not overwrite a paid invoice or recreate a missing exported invoice", ctx do
    {:ok, export} = Accommodation.enqueue(ctx.document.id)
    mark_synced(export)
    add_fee(ctx.booking)
    doc = update!(ctx.document)
    {:ok, update} = Accommodation.enqueue(doc.id)
    [invoice] = update.payload["winstrom"]["faktura-vydana"]
    expect_snapshot(invoice, %{"juhSum" => "100"})
    assert {:error, message} = Accommodation.sync(update.id)
    assert message =~ "úhradu"

    Req.Test.expect(Client, fn conn ->
      assert conn.method == "GET"
      Req.Test.json(conn, %{"winstrom" => %{"faktura-vydana" => []}})
    end)

    assert {:error, message} = Accommodation.sync(update.id)
    assert message =~ "chybí"
  end

  test "does not claim success if ABRA returns the new total but stale line items", ctx do
    {:ok, export} = Accommodation.enqueue(ctx.document.id)
    mark_synced(export)
    add_fee(ctx.booking)
    doc = update!(ctx.document)
    {:ok, update} = Accommodation.enqueue(doc.id)
    [invoice] = update.payload["winstrom"]["faktura-vydana"]
    stale = Map.update!(invoice, "polozkyFaktury", &Enum.take(&1, 1))
    expect_snapshot(stale, %{"sumCelkem" => to_string(doc.total)})

    Req.Test.expect(Client, fn conn ->
      assert conn.method == "POST"
      Req.Test.json(conn, %{"winstrom" => %{"results" => [%{"id" => 42}]}})
    end)

    expect_snapshot(stale, %{"sumCelkem" => to_string(doc.total)})
    assert {:error, message} = Accommodation.sync(update.id)
    assert message =~ "nepotvrdila"
    refute Accommodation.get_export(doc.id).state == "synced"
  end

  defp mark_synced(export),
    do:
      Repo.update!(
        Ecto.Changeset.change(export,
          state: "synced",
          remote_id: "42",
          synced_at: DateTime.utc_now(:second)
        )
      )

  defp update!(doc, attrs \\ %{}) do
    {:ok, preview} = Billing.preview_advance_update(doc.id, attrs)

    {:ok, updated} =
      Billing.update_advance(doc.id, Map.put(attrs, "preview_token", preview.token))

    updated
  end

  defp add_fee(booking) do
    {:ok, _} =
      Billing.save_item(booking.id, %{
        "name" => "Rekreační poplatek",
        "quantity" => "2",
        "nights" => "3",
        "price_per_night" => "50",
        "vat_rate" => "0",
        "tax_mode" => "outside",
        "item_type" => "extra"
      })
  end

  defp expect_snapshot(invoice, overrides \\ %{}) do
    total = Enum.reduce(invoice["polozkyFaktury"], Decimal.new(0), &Decimal.add(&2, &1["cenaMj"]))

    header =
      invoice
      |> Map.merge(%{
        "id" => 42,
        "sumCelkem" => to_string(total),
        "juhSum" => "0",
        "storno" => false
      })
      |> Map.merge(overrides)

    Req.Test.expect(Client, fn conn ->
      assert conn.method == "GET"
      Req.Test.json(conn, %{"winstrom" => %{"faktura-vydana" => [header]}})
    end)

    Req.Test.expect(Client, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path =~ "/polozkyDokladu"

      Req.Test.json(conn, %{
        "winstrom" => %{"faktura-vydana-polozka" => invoice["polozkyFaktury"]}
      })
    end)
  end
end
