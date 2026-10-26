defmodule CozyCheckout.AbraBankPaymentsTest do
  use CozyCheckout.DataCase, async: false
  @moduletag :financial
  import CozyCheckout.BillingFixtures
  alias CozyCheckout.{Billing, Repo}

  alias CozyCheckout.Abra.{
    Accommodation,
    BankConfirmation,
    BankMovement,
    BankPayments,
    BankPaymentSync,
    BankVerification,
    Client,
    TaxReceiptBuilder
  }

  alias CozyCheckout.Billing.{Document, Money, Payment}

  setup do
    previous = Application.get_env(:cozy_checkout, :abra_accommodation)
    options = Req.default_options()
    # Only accounting codes/totals from the supplied XML; no guest data or source identities.
    cfg = [
      enabled: true,
      bank_confirmation_enabled: true,
      enabled_from: ~U[2020-01-01 00:00:00Z],
      base_url: "https://accounting.test",
      company_id: "test",
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
      tax_receipt_outside_mode: "sumOsv"
    ]

    Application.put_env(:cozy_checkout, :abra_accommodation, cfg)
    Req.default_options(plug: {Req.Test, Client})

    on_exit(fn ->
      Application.put_env(:cozy_checkout, :abra_accommodation, previous)
      Req.default_options(options)
    end)

    fixture = billing_fixture()
    doc = issue!(fixture.booking, "advance", %{"amount" => "1234.57"})
    {:ok, export} = Accommodation.enqueue(doc.id)
    export = export |> Ecto.Changeset.change(state: "synced", remote_id: "42") |> Repo.update!()

    raw = %{
      "id" => 7,
      "banka" => "code:TEST",
      "sumCelkem" => "600.00",
      "mena" => "code:CZK",
      "typPohybuK" => "typPohybu.prijem",
      "datVyst" => to_string(Date.add(Billing.today(), -15)),
      "varSym" => doc.variable_symbol,
      "storno" => false,
      "sparovano" => false
    }

    movement =
      %BankMovement{}
      |> Ecto.Changeset.change(
        base_url: cfg[:base_url],
        company_id: cfg[:company_id],
        remote_id: "7",
        account: "code:TEST",
        amount: Decimal.new("600.00"),
        currency: "code:CZK",
        direction: "typPohybu.prijem",
        paid_on: Date.add(Billing.today(), -15),
        variable_symbol: doc.variable_symbol,
        pairing: "unverified",
        raw: raw,
        scan_id: Ecto.UUID.generate()
      )
      |> Repo.insert!()

    {:ok, remote} =
      Agent.start_link(fn ->
        %{
          receipt: nil,
          paired: false,
          linked: false,
          fault: nil,
          overrides: %{},
          foreign: false,
          posts: []
        }
      end)

    Req.Test.stub(Client, fn conn -> respond(conn, remote, raw, export) end)

    %{
      booking: fixture.booking,
      document: doc,
      export: export,
      movement: movement,
      remote: remote,
      cfg: cfg
    }
  end

  test "ZDD preserves XML sample tax totals, local identity and cents; taxable zero is not treated as outside",
       %{cfg: cfg} do
    lines = [
      Money.line("Ubytování", 1, 1, "270040.00", "12"),
      Money.line("Poplatek", 1, 1, "5495.00", "0", "outside")
    ]

    doc = %Document{
      id: Ecto.UUID.generate(),
      kind: "tax_receipt",
      number: "TEST202600001",
      variable_symbol: "3202600001",
      issued_on: Billing.today(),
      due_on: Billing.today(),
      tax_date: Billing.today(),
      snapshot: %{"currency" => "CZK", "customer" => %{"name" => "Test"}},
      lines: lines,
      total: Money.total(lines)
    }

    assert {:ok, payload} = TaxReceiptBuilder.build(doc, cfg)
    [invoice] = payload["winstrom"]["faktura-vydana"]
    assert invoice["kod"] == doc.number
    assert invoice["id"] == "ext:cozy-checkout:accommodation:#{doc.id}"
    assert invoice["sumZklSniz"] == "241107.14"
    assert invoice["sumDphSniz"] == "28932.86"
    assert Decimal.equal?(Decimal.new(invoice["sumOsv"]), "5495")
    assert invoice["primUcet"] == "code:324999"
    assert invoice["dphZaklUcet"] == "code:343100"
    assert invoice["zaokrNaSumK"] == "zaokrNa.zadne"
    refute Map.has_key?(invoice, "rada")
    refute TaxReceiptBuilder.supported_lines?([Money.line("Nula", 1, 1, "10", "0")], cfg)
  end

  test "explicit confirmation creates one payment, ZDD and job atomically; repeated token writes nothing",
       ctx do
    assert {:ok, preview} = BankPayments.preview(ctx.movement.id, ctx.document.id)
    assert Repo.aggregate(Payment, :count) == 0
    assert {:ok, first} = BankPayments.confirm(preview.token)
    assert {:ok, second} = BankPayments.confirm(preview.token)
    assert first.id == second.id
    assert Repo.aggregate(Payment, :count) == 1
    assert Repo.aggregate(BankConfirmation, :count) == 1
    assert Repo.aggregate(Document, :count) == 2
    payment = Repo.get!(Payment, first.payment_id)
    zdd = Billing.get_document!(payment.tax_document_id)
    assert zdd.tax_date == ctx.movement.paid_on
    assert zdd.due_on == ctx.movement.paid_on
    assert Decimal.equal?(payment.amount, "600")
    worker = Oban.Worker.to_string(CozyCheckout.Workers.AbraBankPaymentWorker)
    assert Repo.aggregate(from(j in Oban.Job, where: j.worker == ^worker), :count) == 1
    assert Agent.get(ctx.remote, & &1.posts) == []
  end

  test "fresh changes, foreign pairing and unavailable bank block confirmation before any financial write",
       ctx do
    {:ok, preview} = BankPayments.preview(ctx.movement.id, ctx.document.id)
    Agent.update(ctx.remote, &%{&1 | overrides: %{"sumCelkem" => "601"}})
    assert {:error, _} = BankPayments.confirm(preview.token)
    Agent.update(ctx.remote, &%{&1 | overrides: %{}, foreign: true})
    assert {:error, _} = BankPayments.preview(ctx.movement.id, ctx.document.id)
    Agent.update(ctx.remote, &%{&1 | foreign: false, fault: :unavailable})
    assert {:error, _} = BankPayments.confirm(preview.token)
    assert Repo.aggregate(Payment, :count) == 0
    assert Repo.aggregate(Document, :count) == 1
    assert Agent.get(ctx.remote, & &1.posts) == []
  end

  test "final invoice after preview invalidates the advance confirmation and retains issued history",
       ctx do
    {:ok, preview} = BankPayments.preview(ctx.movement.id, ctx.document.id)
    issue!(ctx.booking, "final")
    assert {:error, _} = BankPayments.confirm(preview.token)
    assert Repo.aggregate(Payment, :count) == 0
    assert Repo.aggregate(BankConfirmation, :count) == 0
  end

  test "failure building ZDD rolls back payment, ZDD and confirmation", ctx do
    # The local document fits its DB column but exceeds ABRA's 20-character limit.
    Repo.update_all(from(s in CozyCheckout.Billing.Series, where: s.kind == "tax_receipt"),
      set: [prefix: String.duplicate("X", 18)]
    )

    {:ok, preview} = BankPayments.preview(ctx.movement.id, ctx.document.id)
    assert {:error, _} = BankPayments.confirm(preview.token)
    assert Repo.aggregate(Payment, :count) == 0
    assert Repo.aggregate(Document, :count) == 1
    assert Repo.aggregate(BankConfirmation, :count) == 0
  end

  for fault <- [:create_timeout, :pair_timeout, :link_timeout] do
    test "lost response at #{fault} recovers without another document, bank receipt or relationship",
         ctx do
      {:ok, preview} = BankPayments.preview(ctx.movement.id, ctx.document.id)
      {:ok, confirmation} = BankPayments.confirm(preview.token)
      Agent.update(ctx.remote, &%{&1 | fault: unquote(fault)})
      assert {:error, _} = BankPaymentSync.sync(confirmation.id)
      assert BankPayments.get(ctx.movement.id).state == "retrying"
      assert :ok = BankPaymentSync.sync(confirmation.id)
      assert BankPayments.get(ctx.movement.id).state == "synced"
      posts = Agent.get(ctx.remote, & &1.posts)
      assert Enum.sort(posts) == Enum.sort([:create, :pair, :link])
      assert :ok = BankPaymentSync.sync(confirmation.id)
      assert Agent.get(ctx.remote, & &1.posts) == posts
      assert Repo.aggregate(Payment, :count) == 1
      assert Repo.aggregate(Document, :count) == 2
    end
  end

  test "remote edits after confirmation become conflicts and preserve local payment/ZDD", ctx do
    {:ok, preview} = BankPayments.preview(ctx.movement.id, ctx.document.id)
    {:ok, confirmation} = BankPayments.confirm(preview.token)
    payment = Repo.get!(Payment, confirmation.payment_id)
    Agent.update(ctx.remote, &%{&1 | overrides: %{"sumCelkem" => "900"}})
    assert {:cancel, _} = BankPaymentSync.sync(confirmation.id)
    assert BankPayments.get(ctx.movement.id).state == "conflict"
    assert Repo.get!(Payment, payment.id) == payment
    assert {:error, _} = BankPayments.retry(confirmation.id)
    assert Agent.get(ctx.remote, & &1.posts) == []
  end

  test "an identical existing remote pairing is reused without another bank matching operation",
       ctx do
    Agent.update(ctx.remote, &%{&1 | paired: true})
    ctx.movement |> Ecto.Changeset.change(pairing: "paired") |> Repo.update!()
    [candidate] = CozyCheckout.Abra.Bank.list()
    assert candidate.document.id == ctx.document.id
    assert candidate.reason =~ "ABRA hlásí párování"
    {:ok, preview} = BankPayments.preview(ctx.movement.id, ctx.document.id)
    {:ok, confirmation} = BankPayments.confirm(preview.token)
    assert :ok = BankPaymentSync.sync(confirmation.id)
    assert Enum.sort(Agent.get(ctx.remote, & &1.posts)) == Enum.sort([:create, :link])
  end

  test "manual duplicate or disabled confirmation cannot add another payment", ctx do
    receipt!(ctx.booking, "600.00", %{
      "paid_on" => to_string(ctx.movement.paid_on),
      "document_id" => ctx.document.id
    })

    {:ok, preview} = BankPayments.preview(ctx.movement.id, ctx.document.id)
    assert {:error, reason} = BankPayments.confirm(preview.token)
    assert reason =~ "ručně"
    assert Repo.aggregate(Payment, :count) == 1
    assert Repo.aggregate(BankConfirmation, :count) == 0

    Application.put_env(
      :cozy_checkout,
      :abra_accommodation,
      Keyword.put(ctx.cfg, :bank_confirmation_enabled, false)
    )

    assert {:error, _} = BankPayments.preview(ctx.movement.id, ctx.document.id)
  end

  test "pending or manually recorded installments cannot exceed the local advance request", ctx do
    receipt!(ctx.booking, "800.00", %{
      "paid_on" => to_string(ctx.movement.paid_on),
      "document_id" => ctx.document.id
    })

    {:ok, preview} = BankPayments.preview(ctx.movement.id, ctx.document.id)
    assert {:error, reason} = BankPayments.confirm(preview.token)
    assert reason =~ "zbývá méně"
    assert Repo.aggregate(Payment, :count) == 1
    assert Repo.aggregate(BankConfirmation, :count) == 0
  end

  test "false pairing flag does not permit partially consumed or unknown relationships", ctx do
    {links, amounts} = relations(%{paired: true, linked: false, foreign: false})
    amounts = Enum.map(amounts, &Map.put(&1, "castka", "100"))

    assert {:error, _} =
             BankVerification.check(
               %{bank: ctx.movement.raw, links: links, amounts: amounts},
               ctx.movement.raw,
               "42"
             )
  end

  test "document graph root is not a payment; real or unaccounted bindings still block confirmation",
       ctx do
    {roots, []} = relations(%{paired: false, linked: false, foreign: false})

    assert {:ok, %{source_paired?: false}} =
             BankVerification.check(
               %{bank: ctx.movement.raw, links: roots, amounts: []},
               ctx.movement.raw,
               "42"
             )

    root_with_binding = hd(roots) |> Map.put("idVazby", 123)

    assert {:error, reason} =
             BankVerification.check(
               %{bank: ctx.movement.raw, links: [root_with_binding], amounts: []},
               ctx.movement.raw,
               "42"
             )

    assert reason =~ "nerozpoznala"
    assert reason =~ "doklad 7"

    amount = %{
      "id" => 123,
      "castka" => "100",
      "typVazbyK" => "typVazbyDokl.uhrada",
      "storno" => false
    }

    assert {:error, reason} =
             BankVerification.check(
               %{bank: ctx.movement.raw, links: roots, amounts: [amount]},
               ctx.movement.raw,
               "42"
             )

    assert reason =~ "bez odpovídajícího"
  end

  defp respond(conn, remote, bank, export) do
    state = Agent.get(remote, & &1)
    [source] = export.payload["winstrom"]["faktura-vydana"]
    path = URI.decode(conn.request_path)
    source_path = "/c/test/faktura-vydana/#{source["id"]}.json"

    cond do
      conn.method == "GET" and path == source_path ->
        remote_source =
          source
          |> Map.merge(%{
            "id" => 42,
            "sumCelkem" => "1234.57",
            "storno" => false,
            "zbyvaUhradit" => if(state.paired, do: "634.57", else: "1234.57")
          })

        Req.Test.json(conn, %{"winstrom" => %{"faktura-vydana" => [remote_source]}})

      conn.method == "GET" and String.starts_with?(path, "/c/test/faktura-vydana/") ->
        if state.receipt,
          do: Req.Test.json(conn, %{"winstrom" => %{"faktura-vydana" => [state.receipt]}}),
          else: Plug.Conn.send_resp(conn, 404, "")

      conn.method == "GET" and path == "/c/test/banka/7.json" ->
        if state.fault == :unavailable do
          Plug.Conn.send_resp(conn, 503, "")
        else
          data = bank |> Map.put("sparovano", state.paired) |> Map.merge(state.overrides)
          Req.Test.json(conn, %{"winstrom" => %{"banka" => [data]}})
        end

      conn.method == "GET" and
          path in ["/c/test/banka/7/vazby.json", "/c/test/banka/7/vazebni-doklady.json"] ->
        {links, amounts} = relations(state)

        if String.ends_with?(path, "/vazby.json"),
          do: Req.Test.json(conn, %{"winstrom" => %{"vazba" => amounts}}),
          else: Req.Test.json(conn, %{"winstrom" => %{"vazebni-doklad" => links}})

      conn.method == "POST" ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)["winstrom"]

        {operation, changes} =
          cond do
            payload["banka"] ->
              [movement] = payload["banka"]
              assert movement["@create"] == "fail"
              refute Map.has_key?(movement, "sumCelkem")
              assert movement["sparovani"]["uhrazovanaFak"]["@castka"] == "600.00"
              {:pair, %{paired: true}}

            hd(payload["faktura-vydana"])["vytvor-vazbu-zdd"] ->
              {:link, %{linked: true}}

            true ->
              [invoice] = payload["faktura-vydana"]
              assert invoice["@create"] == "ok" and invoice["@update"] == "fail"

              total =
                Money.sum(
                  Enum.map(
                    ~w(sumOsv sumZklSniz sumDphSniz sumZklZakl sumDphZakl),
                    &Decimal.new(invoice[&1])
                  )
                )

              {:create,
               %{
                 receipt:
                   Map.merge(invoice, %{
                     "id" => 84,
                     "sumCelkem" => to_string(total),
                     "storno" => false
                   })
               }}
          end

        timeout? =
          state.fault ==
            %{create: :create_timeout, pair: :pair_timeout, link: :link_timeout}[operation]

        Agent.update(
          remote,
          &(&1
            |> Map.merge(changes)
            |> Map.put(:posts, [operation | &1.posts])
            |> Map.put(:fault, if(timeout?, do: nil, else: state.fault)))
        )

        if timeout?,
          do: Req.Test.transport_error(conn, :timeout),
          else:
            Req.Test.json(conn, %{
              "winstrom" => %{"results" => [%{"id" => if(operation == :pair, do: 7, else: 84)}]}
            })

      true ->
        flunk("Unexpected accounting request: #{conn.method} #{path}")
    end
  end

  defp relations(state) do
    pairs =
      if state.paired or state.foreign,
        do: [{11, if(state.foreign, do: 99, else: 42), "typVazbyDokl.uhradaZALOHY", "600.00"}],
        else: []

    pairs =
      if state.linked, do: pairs ++ [{12, 84, "typVazbyDokl.vazbaZDD", "600.00"}], else: pairs

    links =
      Enum.map(pairs, fn {id, doc, type, _} ->
        %{
          "idVazby" => id,
          "idDokl" => doc,
          "typVazbyK" => type,
          "uroven" => 1,
          "modulK" => "modulUcetni.FAV",
          "storno" => false
        }
      end)

    amounts =
      Enum.map(pairs, fn {id, _, type, amount} ->
        %{"id" => id, "typVazbyK" => type, "castka" => amount, "storno" => false}
      end)

    root = %{
      "idDokl" => 7,
      "modulK" => "modulUcetni.BAN",
      "uroven" => 0,
      "typVazbyK" => "",
      "idVazby" => 0,
      "storno" => false
    }

    {[root | links], amounts}
  end
end
