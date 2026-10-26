defmodule CozyCheckout.AbraFinalBankPaymentsTest do
  use CozyCheckout.DataCase, async: false
  @moduletag :financial
  import CozyCheckout.BillingFixtures
  alias CozyCheckout.{Billing, Repo}

  alias CozyCheckout.Abra.{
    AccommodationExport,
    Bank,
    BankConfirmation,
    BankMovement,
    BankPayments,
    BankPaymentSync,
    Client,
    FinalInvoiceBuilder,
    FinalBankPayments,
    TaxReceiptBuilder
  }

  alias CozyCheckout.Billing.{Document, Money, Payment}

  setup do
    old = Application.get_env(:cozy_checkout, :abra_accommodation)
    options = Req.default_options()

    cfg = [
      enabled: true,
      final_bank_confirmation_enabled: true,
      enabled_from: ~U[2020-01-01 00:00:00Z],
      base_url: "https://accounting.test",
      company_id: "accounting-test",
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
      final_enabled: true,
      final_type_code: "FAKTURA",
      final_vat_code: "01-02",
      final_vat_report_code: "A.4-5.AUTO",
      final_service_account: "602001",
      final_fee_account: "345100",
      final_outside_vat_code: "000U",
      final_outside_vat_report_code: "0.0."
    ]

    Application.put_env(:cozy_checkout, :abra_accommodation, cfg)
    Req.default_options(plug: {Req.Test, Client})

    on_exit(fn ->
      Application.put_env(:cozy_checkout, :abra_accommodation, old)
      Req.default_options(options)
    end)

    fixture = billing_fixture()
    # The advance is a deduction, never a direct payment of the final invoice.
    advance = receipt!(fixture.booking, "600.00")
    zdd = Billing.get_document!(advance.tax_document_id)
    doc = issue!(fixture.booking, "final")
    {:ok, totals} = TaxReceiptBuilder.summary_totals(zdd.lines, cfg)

    sources = [
      %{
        "remote_id" => "100",
        "gross" => to_string(zdd.total),
        "totals" => totals,
        "deduction_id" => "ext:test:deduction"
      }
    ]

    {:ok, payload, expected} = FinalInvoiceBuilder.build(doc, sources, cfg)

    export =
      %AccommodationExport{}
      |> Ecto.Changeset.change(
        document_id: doc.id,
        base_url: cfg[:base_url],
        company_id: cfg[:company_id],
        external_id: "ext:cozy-checkout:accommodation:#{doc.id}",
        remote_id: "236",
        state: "synced",
        payload: payload,
        verification: %{"kind" => "final", "sources" => sources, "expected" => expected}
      )
      |> Repo.insert!()

    {:ok, remote} =
      Agent.start_link(fn ->
        %{banks: %{}, paid: %{}, posts: 0, timeout: false, overrides: %{}, foreign: false}
      end)

    Req.Test.stub(Client, &respond(&1, remote, export))
    Map.merge(fixture, %{doc: doc, export: export, remote: remote, cfg: cfg})
  end

  test "full balance pairs existing documents without ZDD or bank creation and is idempotent",
       ctx do
    movement = movement(ctx, "7", FinalBankPayments.payable(ctx.doc))
    [suggestion] = Bank.for_booking(ctx.booking.id)
    assert suggestion.document.id == ctx.doc.id
    assert {:ok, preview} = BankPayments.preview(movement.id, ctx.doc.id)
    assert Repo.aggregate(Payment, :count) == 1
    assert {:ok, confirmation} = BankPayments.confirm(preview.token)
    assert {:ok, same} = BankPayments.confirm(preview.token)
    assert same.id == confirmation.id
    payment = Repo.get!(Payment, confirmation.payment_id)
    assert is_nil(payment.tax_document_id)
    frozen = Billing.get_document!(ctx.doc.id)
    assert :ok = BankPaymentSync.sync(confirmation.id)
    assert :ok = BankPaymentSync.sync(confirmation.id)
    assert BankPayments.get(movement.id).state == "synced"
    assert Agent.get(ctx.remote, & &1.posts) == 1
    assert Repo.aggregate(Payment, :count) == 2
    assert Repo.aggregate(Document, :count) == 2
    assert Billing.get_document!(ctx.doc.id) == frozen
  end

  test "several partial payments settle only the post-deduction amount", ctx do
    first = movement(ctx, "7", Decimal.new("200"))
    second = movement(ctx, "8", Decimal.sub(FinalBankPayments.payable(ctx.doc), "200"))

    for bank <- [first, second] do
      assert {:ok, preview} = BankPayments.preview(bank.id, ctx.doc.id)
      assert {:ok, confirmation} = BankPayments.confirm(preview.token)
      assert :ok = BankPaymentSync.sync(confirmation.id)
    end

    assert Decimal.equal?(Billing.balance(ctx.booking.id).outstanding, 0)
    assert Repo.aggregate(Payment, :count) == 3
    assert Repo.aggregate(Document, :count) == 2
    assert Agent.get(ctx.remote, & &1.posts) == 2
  end

  test "conflicting link and overpayment prevent local and remote writes", ctx do
    bank = movement(ctx, "7", Decimal.add(FinalBankPayments.payable(ctx.doc), 1))
    assert {:error, reason} = BankPayments.preview(bank.id, ctx.doc.id)
    assert reason =~ "Přeplatek"
    bank = movement(ctx, "8", Decimal.new("200"))
    Agent.update(ctx.remote, &%{&1 | foreign: true})
    assert {:error, _} = BankPayments.preview(bank.id, ctx.doc.id)
    assert Repo.aggregate(BankConfirmation, :count) == 0
    assert Repo.aggregate(Payment, :count) == 1
    assert Agent.get(ctx.remote, & &1.posts) == 0
  end

  test "fresh invoice and bank changes invalidate consent and later conflicts preserve payment",
       ctx do
    bank = movement(ctx, "7", Decimal.new("200"))
    {:ok, preview} = BankPayments.preview(bank.id, ctx.doc.id)
    Agent.update(ctx.remote, &%{&1 | overrides: %{"zbyvaUhradit" => "0"}})
    assert {:error, _} = BankPayments.confirm(preview.token)
    Agent.update(ctx.remote, &%{&1 | overrides: %{}})
    {:ok, confirmation} = BankPayments.confirm(preview.token)
    payment = Repo.get!(Payment, confirmation.payment_id)

    Agent.update(ctx.remote, fn state ->
      %{state | banks: Map.update!(state.banks, "7", &Map.put(&1, "sumCelkem", "201"))}
    end)

    assert {:cancel, _} = BankPaymentSync.sync(confirmation.id)
    assert BankPayments.get(bank.id).state == "conflict"
    assert {:error, _} = BankPayments.retry(confirmation.id)
    assert Repo.get!(Payment, payment.id) == payment
    assert Agent.get(ctx.remote, & &1.posts) == 0
  end

  test "lost matching response resumes with read-back and no duplicate payment or match", ctx do
    bank = movement(ctx, "7", Decimal.new("200"))
    {:ok, preview} = BankPayments.preview(bank.id, ctx.doc.id)
    {:ok, confirmation} = BankPayments.confirm(preview.token)
    Agent.update(ctx.remote, &%{&1 | timeout: true})
    assert {:error, _} = BankPaymentSync.sync(confirmation.id)
    assert BankPayments.get(bank.id).state == "retrying"
    assert {:ok, _} = BankPayments.retry(confirmation.id)
    assert :ok = BankPaymentSync.sync(confirmation.id)
    assert BankPayments.get(bank.id).state == "synced"
    assert Repo.aggregate(Payment, :count) == 2
    assert Repo.aggregate(Document, :count) == 2
    assert Agent.get(ctx.remote, & &1.posts) == 1
  end

  defp movement(ctx, id, amount) do
    raw = %{
      "id" => id,
      "banka" => "code:TEST",
      "sumCelkem" => to_string(amount),
      "mena" => "code:CZK",
      "typPohybuK" => "typPohybu.prijem",
      "datVyst" => to_string(Billing.today()),
      "varSym" => ctx.doc.variable_symbol,
      "storno" => false,
      "sparovano" => false
    }

    Agent.update(ctx.remote, &%{&1 | banks: Map.put(&1.banks, id, raw)})

    %BankMovement{}
    |> Ecto.Changeset.change(
      base_url: ctx.cfg[:base_url],
      company_id: ctx.cfg[:company_id],
      remote_id: id,
      account: "code:TEST",
      amount: amount,
      currency: "code:CZK",
      direction: "typPohybu.prijem",
      paid_on: Billing.today(),
      variable_symbol: ctx.doc.variable_symbol,
      pairing: "unverified",
      raw: raw,
      scan_id: Ecto.UUID.generate()
    )
    |> Repo.insert!()
  end

  defp respond(conn, agent, export) do
    state = Agent.get(agent, & &1)
    path = URI.decode(conn.request_path)
    [definition] = export.payload["winstrom"]["faktura-vydana"]
    sources = export.verification["sources"]
    deductions = deduction_rows(sources)
    paid = state.paid |> Map.values() |> Enum.map(&Decimal.new/1) |> Money.sum()

    invoice =
      definition
      |> Map.merge(export.verification["expected"])
      |> Map.merge(%{
        "id" => 236,
        "storno" => false,
        "juhSum" => to_string(paid),
        "zbyvaUhradit" =>
          to_string(Decimal.sub(export.verification["expected"]["sumCelkem"], paid))
      })
      |> Map.merge(state.overrides)

    pairs =
      Enum.map(state.paid, fn {id, amount} ->
        %{
          "id" => "9#{id}",
          "typVazbyK" => "typVazbyDokl.uhrada",
          "storno" => false,
          "castka" => amount,
          "a@ref" => "/v2/c/accounting-test/faktura-vydana/236.json",
          "b@ref" => "/v2/c/accounting-test/banka/#{id}.json"
        }
      end)

    deduction_links =
      Enum.map(deductions, fn row ->
        %{
          "idVazby" => row["id"],
          "idDokl" => "100",
          "modulK" => "modulUcetni.FAV",
          "typVazbyK" => "typVazbyDokl.odpocetZDD",
          "uroven" => 1,
          "storno" => false
        }
      end)

    cond do
      conn.method == "POST" ->
        assert path == "/c/accounting-test/banka.json"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert %{"winstrom" => %{"banka" => [request]}} = Jason.decode!(body)
        assert Map.keys(request) |> Enum.sort() == Enum.sort(~w(@create @update id sparovani))
        assert request["@create"] == "fail" and request["@update"] == "ok"
        assert request["sparovani"]["zbytek"] == "ne"

        assert [%{"@content" => "236", "@type" => "faktura-vydana", "@castka" => amount}] =
                 request["sparovani"]["uhrazovanaFak"]

        assert amount == state.banks[request["id"]]["sumCelkem"]
        refute Map.has_key?(state.paid, request["id"])

        Agent.update(
          agent,
          &%{
            &1
            | posts: &1.posts + 1,
              paid: Map.put(&1.paid, request["id"], amount),
              timeout: false
          }
        )

        if state.timeout,
          do: Req.Test.transport_error(conn, :timeout),
          else: json(conn, "results", [%{"id" => request["id"]}])

      String.contains?(path, "/banka/") ->
        id = path |> String.split("/") |> Enum.at(4) |> String.replace_suffix(".json", "")
        bank = Map.fetch!(state.banks, id)
        binding = Enum.find(pairs, &String.ends_with?(&1["b@ref"], "/#{id}.json"))

        links =
          if binding,
            do: [
              %{
                "idVazby" => binding["id"],
                "idDokl" => 236,
                "modulK" => "modulUcetni.FAV",
                "uroven" => 1,
                "storno" => false,
                "typVazbyK" => "typVazbyDokl.uhrada"
              }
            ],
            else: []

        links =
          if state.foreign,
            do: [
              %{
                "idVazby" => 999,
                "idDokl" => 999,
                "modulK" => "modulUcetni.FAV",
                "uroven" => 1,
                "storno" => false,
                "typVazbyK" => "typVazbyDokl.uhrada"
              }
            ],
            else: links

        cond do
          String.ends_with?(path, "/vazby.json") ->
            json(conn, "vazba", if(binding, do: [binding], else: []))

          String.ends_with?(path, "/vazebni-doklady.json") ->
            json(conn, "vazebni-doklad", links)

          true ->
            json(conn, "banka", [Map.put(bank, "sparovano", not is_nil(binding))])
        end

      String.ends_with?(path, "/polozkyDokladu.json") ->
        json(conn, "faktura-vydana-polozka", definition["polozkyFaktury"] ++ deductions)

      String.ends_with?(path, "/vazebni-doklady.json") ->
        links =
          Enum.map(
            pairs,
            &%{
              "idVazby" => &1["id"],
              "idDokl" => bank_ref(&1),
              "modulK" => "modulUcetni.BAN",
              "uroven" => 1,
              "storno" => false,
              "typVazbyK" => "typVazbyDokl.uhrada"
            }
          )

        json(conn, "vazebni-doklad", deduction_links ++ links)

      String.ends_with?(path, "/vazby.json") ->
        bindings =
          if String.contains?(path, "/100/"),
            do:
              Enum.map(
                deductions,
                &%{
                  "id" => &1["id"],
                  "typVazbyK" => "typVazbyDokl.odpocetZDD",
                  "storno" => false,
                  "a@ref" => "/v2/c/accounting-test/faktura-vydana-polozka/#{&1["id"]}.json",
                  "b@ref" => "/v2/c/accounting-test/faktura-vydana/100.json"
                }
              ),
            else: pairs

        json(conn, "vazba", bindings)

      conn.method == "GET" ->
        json(conn, "faktura-vydana", [invoice])

      true ->
        flunk("Unexpected ABRA request")
    end
  end

  defp bank_ref(binding),
    do: binding["b@ref"] |> String.split("/") |> List.last() |> String.replace_suffix(".json", "")

  defp json(conn, key, rows), do: Req.Test.json(conn, %{"winstrom" => %{key => rows}})

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
        "id" =>
          source["remote_id"] <>
            if(vat_key == "sumDphSniz", do: "1", else: if(vat_key, do: "2", else: "3")),
        "storno" => false,
        "typPolozkyK" => "typPolozky.odpocetZdd",
        "typSzbDphK" => type,
        "sumZkl" => to_string(net),
        "sumDph" => to_string(vat),
        "sumCelkem" => to_string(Decimal.add(net, vat))
      }
    end
  end
end
