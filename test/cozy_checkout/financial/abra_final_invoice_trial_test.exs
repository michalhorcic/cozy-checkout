defmodule CozyCheckout.AbraFinalInvoiceTrialTest do
  use CozyCheckout.DataCase, async: false
  @moduletag :financial
  import CozyCheckout.BillingFixtures
  alias CozyCheckout.{Billing, Repo}

  alias CozyCheckout.Abra.{
    Accommodation,
    AccommodationExport,
    BankConfirmation,
    BankMovement,
    Client,
    TaxReceiptBuilder
  }

  alias CozyCheckout.Billing.{Document, Payment}

  setup do
    old = Application.get_env(:cozy_checkout, :abra_accommodation)
    options = Req.default_options()

    cfg = [
      enabled: true,
      enabled_from: ~U[2020-01-01 00:00:00Z],
      base_url: "https://accounting.test",
      company_id: "trial",
      username: "test",
      password: "test",
      advance_type_code: "ZÁLOHA",
      bank_account_code: "TEST",
      tax_receipt_type_code: "ZDD",
      tax_receipt_vat_code: "01-02",
      tax_receipt_vat_report_code: "A.4-5.AUTO",
      tax_receipt_operation_code: "ZÁLOHA PŘIJATÁ",
      tax_receipt_primary_account: "324999",
      tax_receipt_counter_account: "324001",
      tax_receipt_vat12_account: "343200",
      tax_receipt_vat21_account: "343100",
      tax_receipt_outside_mode: "sumOsv",
      final_trial_enabled: true,
      final_trial_base_url: "https://accounting.test",
      final_trial_company_id: "trial",
      final_trial_type_code: "FAKTURA",
      final_trial_vat_code: "01-02",
      final_trial_vat_report_code: "A.4-5.AUTO",
      final_trial_service_account: "602001",
      final_trial_fee_account: "345100",
      final_trial_outside_vat_code: "000U",
      final_trial_outside_vat_report_code: "0.0."
    ]

    Application.put_env(:cozy_checkout, :abra_accommodation, cfg)
    Req.default_options(plug: {Req.Test, Client})

    on_exit(fn ->
      Application.put_env(:cozy_checkout, :abra_accommodation, old)
      Req.default_options(options)
    end)

    fixture = billing_fixture()
    advance = issue!(fixture.booking, "advance", %{"percent" => "100"})
    {:ok, source_export} = Accommodation.enqueue(advance.id)

    source_export =
      source_export |> Ecto.Changeset.change(state: "synced", remote_id: "42") |> Repo.update!()

    {:ok, remote} =
      Agent.start_link(fn ->
        %{
          export: nil,
          invoice: nil,
          sources: %{},
          posts: 0,
          available_reads: 0,
          consumed: false,
          fault: nil
        }
      end)

    Req.Test.stub(Client, &respond(&1, remote))

    Map.merge(fixture, %{advance: advance, source_export: source_export, remote: remote, cfg: cfg})
  end

  test "two fractional ZDDs and outside fee retain original tax bases and produce real deductions without new receipts",
       ctx do
    {:ok, _} =
      Billing.save_item(ctx.booking.id, %{
        name: "Poplatek",
        quantity: 1,
        nights: 1,
        price_per_night: "35",
        vat_rate: "0",
        tax_mode: "outside",
        item_type: "extra"
      })

    seed_receipt(ctx, "600.01", 100)
    seed_receipt(ctx, "400.02", 101)
    {doc, export} = final_export(ctx)
    [invoice] = export.payload["winstrom"]["faktura-vydana"]

    for {item, original} <- Enum.zip(invoice["polozkyFaktury"], doc.lines) do
      assert Decimal.equal?(
               Decimal.new(item["mnozMj"]),
               Decimal.mult(original["quantity"], original["nights"])
             )

      assert item["cenaMj"] == original["unit"]
    end

    deductions = invoice["odpocty-zaloh"]["odpocet"]
    assert length(deductions) == 2
    assert length(Enum.uniq_by(deductions, & &1["id"])) == 2

    for deduction <- deductions do
      source =
        Enum.find(export.verification["sources"], &(&1["remote_id"] == deduction["doklad"]))

      assert deduction["castkyBezDph"] == true
      assert deduction["skupPlneni"] == "OTHER"
      assert deduction["castkaSnizMen"] == source["totals"]["sumZklSniz"]
      refute Map.has_key?(deduction, "prijmoutDoporuceni")
    end

    fee = Enum.find(invoice["polozkyFaktury"], &(&1["nazev"] == "Poplatek"))
    assert fee["zklDalUcet"] == "code:345100"
    assert fee["clenDph"] == "code:000U"

    assert Decimal.equal?(
             Decimal.new(export.verification["expected"]["sumCelkem"]),
             Decimal.sub(doc.total, "1000.03")
           )

    assert :ok = Accommodation.sync(export.id)
    assert :ok = Accommodation.sync(export.id)
    assert Agent.get(ctx.remote, & &1.posts) == 1
    assert Repo.aggregate(Payment, :count) == 2
    assert Repo.aggregate(Document, :count) == 4
  end

  test "final invoice without a paid advance exports no deduction and no payment", ctx do
    {doc, export} = final_export(ctx)
    [invoice] = export.payload["winstrom"]["faktura-vydana"]
    refute Map.has_key?(invoice, "odpocty-zaloh")
    assert export.verification["sources"] == []
    assert Decimal.equal?(Decimal.new(export.verification["expected"]["sumCelkem"]), doc.total)
    assert :ok = Accommodation.sync(export.id)
    assert Repo.aggregate(Payment, :count) == 0
  end

  test "fully prepaid stay has zero invoice balance and creates no balancing receipt", ctx do
    seed_receipt(ctx, to_string(ctx.advance.total), 100)
    {_doc, export} = final_export(ctx)
    assert Decimal.equal?(Decimal.new(export.verification["expected"]["sumCelkem"]), 0)
    assert :ok = Accommodation.sync(export.id)
    assert Repo.aggregate(Payment, :count) == 1
    assert Agent.get(ctx.remote, & &1.posts) == 1
  end

  test "disabled or unpinned trial and unfinished source prevent enqueue", ctx do
    confirmation = seed_receipt(ctx, "600", 100)
    doc = issue!(ctx.booking, "final")

    for attrs <- [
          [final_trial_enabled: false],
          [final_trial_company_id: "other"],
          [final_trial_base_url: "https://other.test"]
        ] do
      configure(ctx.cfg, attrs)
      assert {:error, _} = Accommodation.enqueue(doc.id)
    end

    configure(ctx.cfg, [])
    confirmation |> Ecto.Changeset.change(state: "conflict") |> Repo.update!()
    assert {:error, _} = Accommodation.enqueue(doc.id)
    refute Accommodation.get_export(doc.id)
    assert Repo.aggregate(AccommodationExport, :count) == 1
  end

  test "already deducted source stops before creation and preserves frozen export", ctx do
    seed_receipt(ctx, "600", 100)
    {_doc, export} = final_export(ctx)
    Agent.update(ctx.remote, &%{&1 | consumed: true})
    assert {:error, reason} = Accommodation.sync(export.id)
    assert reason =~ "odečteno"
    assert Agent.get(ctx.remote, & &1.posts) == 0
    assert Accommodation.get_export(export.document_id).payload == export.payload
  end

  test "lost response recovers by external identity even when source balances are now exhausted",
       ctx do
    seed_receipt(ctx, "600", 100)
    {_doc, export} = final_export(ctx)
    Agent.update(ctx.remote, &%{&1 | fault: :timeout})
    assert {:error, _} = Accommodation.sync(export.id)
    reads = Agent.get(ctx.remote, & &1.available_reads)
    assert :ok = Accommodation.sync(export.id)
    assert Agent.get(ctx.remote, & &1.available_reads) == reads
    assert Agent.get(ctx.remote, & &1.posts) == 1
    assert Repo.aggregate(Payment, :count) == 1
  end

  for fault <- [:tax_mismatch, :wrong_source] do
    test "#{fault} in returned invoice blocks success without overwriting or another creation",
         ctx do
      seed_receipt(ctx, "600", 100)
      {_doc, export} = final_export(ctx)
      Agent.update(ctx.remote, &%{&1 | fault: unquote(fault)})
      assert {:cancel, _} = Accommodation.sync(export.id, true)
      assert Accommodation.get_export(export.document_id).state == "failed"
      assert {:ok, _} = Accommodation.enqueue(export.document_id)
      assert {:cancel, _} = Accommodation.sync(export.id, true)
      assert Agent.get(ctx.remote, & &1.posts) == 1
      assert Repo.aggregate(Payment, :count) == 1
    end
  end

  defp seed_receipt(ctx, amount, id) do
    payment = receipt!(ctx.booking, amount, %{"document_id" => ctx.advance.id})
    zdd = Billing.get_document!(payment.tax_document_id)
    {:ok, payload} = TaxReceiptBuilder.build(zdd, ctx.cfg)
    [invoice] = payload["winstrom"]["faktura-vydana"]
    {:ok, totals} = TaxReceiptBuilder.summary_totals(zdd.lines, ctx.cfg)

    movement =
      %BankMovement{}
      |> Ecto.Changeset.change(
        base_url: ctx.cfg[:base_url],
        company_id: ctx.cfg[:company_id],
        remote_id: to_string(id),
        account: "code:TEST",
        amount: payment.amount,
        currency: "code:CZK",
        direction: "typPohybu.prijem",
        paid_on: payment.paid_on,
        pairing: "paired",
        raw: %{},
        scan_id: Ecto.UUID.generate()
      )
      |> Repo.insert!()

    confirmation =
      %BankConfirmation{}
      |> Ecto.Changeset.change(
        movement_id: movement.id,
        payment_id: payment.id,
        source_export_id: ctx.source_export.id,
        base_url: ctx.cfg[:base_url],
        company_id: ctx.cfg[:company_id],
        bank_snapshot: %{},
        receipt_payload: payload,
        remote_receipt_id: to_string(id),
        state: "synced"
      )
      |> Repo.insert!()

    remote_invoice =
      Map.merge(invoice, %{"id" => id, "storno" => false, "sumCelkem" => to_string(zdd.total)})

    Agent.update(ctx.remote, fn state ->
      %{
        state
        | sources:
            Map.put(state.sources, to_string(id), %{
              invoice: remote_invoice,
              external_id: invoice["id"],
              totals: totals
            })
      }
    end)

    confirmation
  end

  defp final_export(ctx) do
    doc = issue!(ctx.booking, "final")
    assert {:ok, export} = Accommodation.enqueue(doc.id)
    Agent.update(ctx.remote, &%{&1 | export: export})
    {doc, export}
  end

  defp respond(conn, agent) do
    state = Agent.get(agent, & &1)
    path = URI.decode(conn.request_path)

    source =
      Enum.find_value(state.sources, fn {_id, source} ->
        if String.contains?(path, source.external_id), do: source
      end)

    cond do
      conn.method == "GET" and source ->
        json(conn, "faktura-vydana", [source.invoice])

      conn.method == "GET" and String.ends_with?(path, "/castky-k-odpoctu.json") ->
        id = path |> String.split("/") |> Enum.at(-2)
        source = Map.fetch!(state.sources, id)
        exhausted? = state.consumed or not is_nil(state.invoice)

        totals =
          if exhausted?,
            do: Map.new(source.totals, fn {key, _} -> {key, "0.00"} end),
            else: source.totals

        Agent.update(agent, &%{&1 | available_reads: &1.available_reads + 1})
        json(conn, "castky-k-odpoctu", [totals])

      conn.method == "GET" and String.ends_with?(path, "/polozkyFaktury.json") ->
        [invoice] = state.export.payload["winstrom"]["faktura-vydana"]

        ordinary =
          Enum.map(invoice["polozkyFaktury"], &Map.put(&1, "typPolozkyK", "typPolozky.obecny"))

        json(
          conn,
          "faktura-vydana-polozka",
          ordinary ++ deduction_rows(state.export.verification["sources"])
        )

      conn.method == "GET" and String.ends_with?(path, "/vazebni-doklady.json") ->
        links =
          Enum.with_index(state.export.verification["sources"], 1)
          |> Enum.map(fn {source, index} ->
            %{
              "idVazby" => index,
              "idDokl" =>
                if(state.fault == :wrong_source, do: "other", else: source["remote_id"]),
              "modulK" => "modulUcetni.FAV",
              "typVazbyK" => "typVazbyDokl.odpocetZDD",
              "uroven" => 1,
              "storno" => false
            }
          end)

        json(conn, "vazebni-doklad", links)

      conn.method == "GET" and String.ends_with?(path, "/vazby.json") ->
        amounts =
          Enum.with_index(state.export.verification["sources"], 1)
          |> Enum.map(fn {source, index} ->
            %{
              "id" => index,
              "castka" => source["gross"],
              "typVazbyK" => "typVazbyDokl.odpocetZDD",
              "storno" => false
            }
          end)

        json(conn, "vazba", amounts)

      conn.method == "GET" ->
        if state.invoice,
          do: json(conn, "faktura-vydana", [state.invoice]),
          else: Plug.Conn.send_resp(conn, 404, "")

      conn.method == "POST" ->
        assert path == "/c/trial/faktura-vydana.json"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == state.export.payload
        [invoice] = state.export.payload["winstrom"]["faktura-vydana"]
        assert invoice["@create"] == "ok" and invoice["@update"] == "fail"
        refute Map.has_key?(invoice, "hotovostni-uhrada")

        remote =
          Map.merge(invoice, state.export.verification["expected"])
          |> Map.merge(%{"id" => 236, "storno" => false})

        remote =
          if state.fault == :tax_mismatch,
            do: Map.update!(remote, "sumDphSniz", &to_string(Decimal.add(&1, "0.01"))),
            else: remote

        Agent.update(agent, &%{&1 | invoice: remote, posts: &1.posts + 1})

        if state.fault == :timeout,
          do: Req.Test.transport_error(conn, :timeout),
          else: json(conn, "results", [%{"id" => 236}])

      true ->
        flunk("Unexpected final-invoice request")
    end
  end

  defp deduction_rows(sources) do
    for source <- sources,
        {net_key, vat_key, type} <- [
          {"sumZklSniz", "sumDphSniz", "typSzbDph.dphSniz"},
          {"sumZklZakl", "sumDphZakl", "typSzbDph.dphZakl"},
          {"sumOsv", nil, "typSzbDph.dphOsv"}
        ],
        net = Decimal.negate(Decimal.new(source["totals"][net_key])),
        vat =
          if(vat_key,
            do: Decimal.negate(Decimal.new(source["totals"][vat_key])),
            else: Decimal.new(0)
          ),
        not Decimal.equal?(net, 0) or not Decimal.equal?(vat, 0) do
      %{
        "typPolozkyK" => "typPolozky.odpocetZdd",
        "typSzbDphK" => type,
        "sumZkl" => to_string(net),
        "sumDph" => to_string(vat),
        "sumCelkem" => to_string(Decimal.add(net, vat))
      }
    end
  end

  defp json(conn, key, rows), do: Req.Test.json(conn, %{"winstrom" => %{key => rows}})

  defp configure(cfg, changes),
    do: Application.put_env(:cozy_checkout, :abra_accommodation, Keyword.merge(cfg, changes))
end
