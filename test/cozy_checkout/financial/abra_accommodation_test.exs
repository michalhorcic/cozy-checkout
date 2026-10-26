defmodule CozyCheckout.AbraAccommodationTest do
  use CozyCheckout.DataCase, async: false
  @moduletag :financial
  import CozyCheckout.BillingFixtures
  alias CozyCheckout.Abra.{Accommodation, AccommodationExport, AdvanceBuilder, Client}
  alias CozyCheckout.Workers.AbraAccommodationWorker

  setup do
    old_config = Application.get_env(:cozy_checkout, :abra_accommodation)
    old_options = Req.default_options()

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

    Req.default_options(plug: {Req.Test, Client})
    Req.Test.verify_on_exit!()

    on_exit(fn ->
      Application.put_env(:cozy_checkout, :abra_accommodation, old_config)
      Req.default_options(old_options)
    end)

    fixture = billing_fixture()

    Map.put(
      fixture,
      :document,
      issue_without_abra!(fixture.booking, "advance", %{"amount" => "1234.57"})
    )
  end

  test "builder preserves the issued snapshot and non-accounting advance mapping", %{
    document: doc
  } do
    assert {:ok, payload} = AdvanceBuilder.build(doc, Accommodation.config())
    [invoice] = payload["winstrom"]["faktura-vydana"]
    assert invoice["kod"] == doc.number
    assert String.starts_with?(doc.number, "COZY-ZF")
    assert invoice["varSym"] == doc.variable_symbol
    assert invoice["varSym"] == "1#{doc.issued_on.year}00001"
    assert invoice["nazFirmy"] == doc.snapshot["customer"]["name"]
    assert invoice["kontaktEmail"] == doc.snapshot["customer"]["email"]
    refute Map.has_key?(invoice, "email")
    assert invoice["typDokl"] == "code:ZÁLOHA"
    refute Map.has_key?(invoice, "rada")
    assert invoice["clenDph"] == "code:000U"
    assert invoice["ucetni"] == false
    assert invoice["poznam"] =~ "Záloha zadaná částkou: 1 234,57 CZK"
    refute Map.has_key?(invoice, "hotovostni-uhrada")
    refute Map.has_key?(invoice, "duzpPuv")

    assert {:error, _} =
             AdvanceBuilder.build(
               %{doc | number: String.duplicate("X", 21)},
               Accommodation.config()
             )

    alias CozyCheckout.Billing.Money

    lines = [
      Money.line("Ubytování", 1, 1, "112.00", "12"),
      Money.line("Služba", 1, 1, "121.00", "21"),
      Money.line("Poplatek", 1, 1, "35.00", "0", "outside")
    ]

    assert {:ok, mixed} =
             AdvanceBuilder.build(
               %{doc | lines: lines, total: Money.total(lines)},
               Accommodation.config()
             )

    [mixed_invoice] = mixed["winstrom"]["faktura-vydana"]
    [stay, service, fee] = mixed_invoice["polozkyFaktury"]
    assert stay["typSzbDphK"] == "typSzbDph.dphSniz"
    assert service["typSzbDphK"] == "typSzbDph.dphZakl"
    assert fee["typSzbDphK"] == "typSzbDph.dphOsv"
    assert fee["typCenyDphK"] == "typCeny.bezDph"
    assert fee["cenaMj"] == "35.00"
  end

  test "enqueue is atomic and repeated clicks keep one export, payload and active job", %{
    document: doc
  } do
    assert {:error, :cancelled} =
             Repo.transaction(fn ->
               assert {:ok, _} = Accommodation.enqueue(doc.id)
               Repo.rollback(:cancelled)
             end)

    assert Repo.aggregate(AccommodationExport, :count) == 0

    assert {:ok, first} = Accommodation.enqueue(doc.id)
    assert {:ok, second} = Accommodation.enqueue(doc.id)
    assert first.id == second.id
    assert first.payload == second.payload
    assert Repo.aggregate(AccommodationExport, :count) == 1
    worker = Oban.Worker.to_string(AbraAccommodationWorker)
    assert Repo.aggregate(from(j in Oban.Job, where: j.worker == ^worker), :count) == 1
  end

  test "note describes the original stay separately from the requested advance, with legacy fallback",
       %{document: doc} do
    alias CozyCheckout.Billing.Money

    calculation = %{
      "method" => "percent",
      "percent" => "50",
      "stay_total" => "1200.00",
      "amount" => "600.00",
      "lines" => [Money.line("Původní ubytování", 2, 3, "200.00", "12")]
    }

    snapshot = Map.put(doc.snapshot, "advance_calculation", calculation)

    note_doc = %{
      doc
      | snapshot: snapshot,
        total: Decimal.new("600.00"),
        lines: Money.allocate(calculation["lines"], Decimal.new("600.00"))
    }

    assert {:ok, payload} = AdvanceBuilder.build(note_doc, Accommodation.config())
    [invoice] = payload["winstrom"]["faktura-vydana"]
    assert invoice["poznam"] =~ "Původní ubytování: 2,00 × 3,00 × 200,00 CZK = 1 200,00 CZK"
    assert invoice["poznam"] =~ "Celková cena pobytu: 1 200,00 CZK"
    assert invoice["poznam"] =~ "50,00 % z 1 200,00 CZK = 600,00 CZK"
    assert invoice["polozkyFaktury"] != calculation["lines"]

    assert {:ok, legacy} =
             AdvanceBuilder.build(
               %{doc | snapshot: Map.delete(doc.snapshot, "advance_calculation")},
               Accommodation.config()
             )

    [legacy_invoice] = legacy["winstrom"]["faktura-vydana"]
    assert legacy_invoice["poznam"] =~ "Původní rozpis položek nebyl u tohoto dokladu uložen."
    refute legacy_invoice["poznam"] =~ "Přijatá záloha"
  end

  test "disabled export, old bookings and other document kinds cannot enqueue", %{
    booking: booking,
    document: doc
  } do
    configure(enabled: false)
    assert {:error, _} = Accommodation.enqueue(doc.id)
    configure(enabled: true, enabled_from: DateTime.add(DateTime.utc_now(), 60, :second))
    assert {:error, _} = Accommodation.enqueue(doc.id)
    configure(enabled_from: ~U[2020-01-01 00:00:00Z])
    final = issue_without_abra!(booking, "final")
    configure(enabled: false)
    assert {:error, _} = Accommodation.enqueue(final.id)
    assert Repo.aggregate(AccommodationExport, :count) == 0
  end

  test "successful delivery reads back the amount and a second run makes no HTTP calls", %{
    document: doc
  } do
    {:ok, export} = Accommodation.enqueue(doc.id)
    remote = remote_invoice(doc)

    Req.Test.expect(Client, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path =~ "/c/test-accommodation/faktura-vydana/"
      Req.Test.json(conn, %{"winstrom" => %{"faktura-vydana" => []}})
    end)

    Req.Test.expect(Client, fn conn ->
      assert conn.method == "POST"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body) == export.payload

      [invoice] = get_in(Jason.decode!(body), ["winstrom", "faktura-vydana"])
      assert invoice["@create"] == "ok"
      assert invoice["@update"] == "fail"
      refute Map.has_key?(invoice, "@action")

      Req.Test.json(conn, %{"winstrom" => %{"results" => [%{"id" => 42}]}})
    end)

    expect_remote(remote)
    assert :ok = Accommodation.sync(export.id)
    assert :ok = Accommodation.sync(export.id)
    assert %{state: "synced", remote_id: "42", attempts: 1} = Accommodation.get_export(doc.id)
  end

  test "lost import response recovers by external identity without a second POST", %{
    document: doc
  } do
    {:ok, export} = Accommodation.enqueue(doc.id)

    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{"winstrom" => %{"faktura-vydana" => []}})
    end)

    Req.Test.expect(Client, fn conn -> Req.Test.transport_error(conn, :timeout) end)
    assert {:error, _} = Accommodation.sync(export.id)
    assert Accommodation.get_export(doc.id).state == "retrying"
    expect_remote(remote_invoice(doc))
    assert :ok = Accommodation.sync(export.id)
    assert Accommodation.get_export(doc.id).attempts == 2
  end

  test "mismatching remote document is never overwritten and failure can be manually retried", %{
    document: doc
  } do
    {:ok, export} = Accommodation.enqueue(doc.id)
    expect_remote(Map.put(remote_invoice(doc), "sumCelkem", "999.00"))
    assert {:cancel, _} = Accommodation.sync(export.id, true)
    assert Accommodation.get_export(doc.id).state == "failed"
    assert {:ok, retry} = Accommodation.enqueue(doc.id)
    assert retry.payload == export.payload
    assert retry.state == "queued"
  end

  test "changing the target pauses delivery and cannot repurpose a saved export", %{document: doc} do
    {:ok, export} = Accommodation.enqueue(doc.id)
    configure(company_id: "another-company")
    assert {:cancel, _} = Accommodation.sync(export.id)
    assert {:error, _} = Accommodation.enqueue(doc.id)
    assert Accommodation.get_export(doc.id).company_id == "test-accommodation"
    assert Accommodation.get_export(doc.id).payload == export.payload
  end

  test "automatic issuance commits one intent and job, repeats safely and rolls back together",
       ctx do
    assert Accommodation.get_export(ctx.document.id) == nil

    assert {:error, :cancelled} =
             Repo.transaction(fn ->
               doc = issue!(ctx.booking, "advance", %{"amount" => "500"})
               assert Accommodation.get_export(doc.id).payload == %{}
               Repo.rollback(:cancelled)
             end)

    assert Repo.aggregate(AccommodationExport, :count) == 0
    doc = issue!(ctx.booking, "advance", %{"amount" => "500"})

    assert {:ok, same} =
             CozyCheckout.Billing.issue(ctx.booking.id, "advance", %{}, doc.request_id)

    assert same.id == doc.id
    export = Accommodation.get_export(doc.id)
    assert export.payload == %{}
    assert export.verification["automatic"]
    assert Repo.aggregate(AccommodationExport, :count) == 1
    worker = Oban.Worker.to_string(AbraAccommodationWorker)
    assert Repo.aggregate(from(j in Oban.Job, where: j.worker == ^worker), :count) == 1
  end

  test "configuration failure never blocks issuance and can resume the same intent", ctx do
    configure(username: nil, base_url: nil, company_id: nil)
    doc = issue!(ctx.booking, "advance", %{"amount" => "500"})
    export = Accommodation.get_export(doc.id)
    assert {:cancel, _} = Accommodation.sync(export.id)
    assert Accommodation.get_export(doc.id).state == "failed"
    assert [%{id: id, category: "document"}] = CozyCheckout.Abra.Transfers.list()
    assert id == export.id

    configure(
      username: "test-user",
      base_url: "https://accounting.test",
      company_id: "test-accommodation"
    )

    assert {:ok, retried} = CozyCheckout.Abra.Transfers.retry("document", export.id)
    assert retried.id == export.id
    expect_remote(remote_invoice(doc))
    assert :ok = Accommodation.sync(export.id)
    assert Accommodation.get_export(doc.id).state == "synced"
    assert CozyCheckout.Billing.get_document!(doc.id) == doc
  end

  test "automatic timeout resumes a frozen payload by external identity without a second POST",
       ctx do
    doc = issue!(ctx.booking, "advance", %{"amount" => "500"})
    export = Accommodation.get_export(doc.id)

    Req.Test.expect(Client, fn conn ->
      Req.Test.json(conn, %{"winstrom" => %{"faktura-vydana" => []}})
    end)

    Req.Test.expect(Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body) == Accommodation.get_export(doc.id).payload
      Req.Test.transport_error(conn, :timeout)
    end)

    assert {:error, _} = Accommodation.sync(export.id)
    frozen = Accommodation.get_export(doc.id).payload
    refute frozen == %{}
    configure(advance_type_code: "CHANGED")
    expect_remote(remote_invoice(doc))
    assert :ok = Accommodation.sync(export.id)
    assert Accommodation.get_export(doc.id).payload == frozen
    assert Repo.aggregate(AccommodationExport, :count) == 1
  end

  test "automatic export respects the switch, cutoff and saved target without backfill", ctx do
    configure(enabled_from: DateTime.add(DateTime.utc_now(), 60, :second))

    old = issue!(ctx.booking, "advance", %{"amount" => "500"})
    assert Accommodation.get_export(old.id) == nil
    configure(enabled_from: ~U[2020-01-01 00:00:00Z], enabled: false)
    manual = issue!(ctx.booking, "advance", %{"amount" => "500"})
    assert Accommodation.get_export(manual.id) == nil
    configure(enabled: true)
    doc = issue!(ctx.booking, "advance", %{"amount" => "500"})
    export = Accommodation.get_export(doc.id)
    configure(company_id: "other")
    assert {:cancel, _} = Accommodation.sync(export.id)
    assert Accommodation.get_export(doc.id).payload == %{}
    assert Accommodation.get_export(doc.id).company_id == "test-accommodation"
    assert Accommodation.get_export(ctx.document.id) == nil
  end

  test "unexpected worker errors remain visible and preserve the issued document", %{
    document: doc
  } do
    {:ok, export} = Accommodation.enqueue(doc.id)
    Req.Test.expect(Client, fn _conn -> raise "transport crashed" end)
    job = %Oban.Job{args: %{"export_id" => export.id}, attempt: 5, max_attempts: 5}
    assert_raise RuntimeError, "transport crashed", fn -> AbraAccommodationWorker.perform(job) end
    assert Accommodation.get_export(doc.id).state == "failed"
    assert Accommodation.get_export(doc.id).error =~ "neočekávaná chyba"
    assert CozyCheckout.Billing.get_document!(doc.id) == doc
  end

  defp configure(attrs),
    do:
      Application.put_env(
        :cozy_checkout,
        :abra_accommodation,
        Keyword.merge(Accommodation.config(), attrs)
      )

  defp remote_invoice(doc) do
    %{
      "id" => 42,
      "kod" => doc.number,
      "varSym" => doc.variable_symbol,
      "sumCelkem" => to_string(doc.total),
      "mena" => "code:CZK",
      "typDokl" => "code:ZÁLOHA",
      "rada" => "",
      "bankovniUcet" => "code:TEST-UCET",
      "ucetni" => false,
      "clenDph" => "code:000U",
      "clenKonVykDph" => "code:0.0."
    }
  end

  defp expect_remote(invoice) do
    Req.Test.expect(Client, fn conn ->
      assert conn.method == "GET"
      Req.Test.json(conn, %{"winstrom" => %{"faktura-vydana" => [invoice]}})
    end)
  end
end
