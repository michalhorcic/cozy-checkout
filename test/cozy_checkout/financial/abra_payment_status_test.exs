defmodule CozyCheckout.AbraPaymentStatusTest do
  use CozyCheckout.DataCase, async: false
  use Oban.Testing, repo: CozyCheckout.Repo
  @moduletag :financial
  import CozyCheckout.BillingFixtures
  alias CozyCheckout.{Billing, Repo}
  alias CozyCheckout.Abra.{Accommodation, AccommodationExport, Client, PaymentStatus}
  alias CozyCheckout.Billing.{BookingSummary, Document, Payment}
  alias CozyCheckout.Workers.AbraPaymentStatusWorker

  setup do
    previous = Accommodation.config()
    options = Req.default_options()

    Application.put_env(:cozy_checkout, :abra_accommodation,
      enabled: true,
      enabled_from: ~U[2020-01-01 00:00:00Z],
      base_url: "https://accounting.test",
      company_id: "payments-test",
      username: "test-user",
      password: "test-password"
    )

    Req.default_options(plug: {Req.Test, Client})
    Req.Test.verify_on_exit!()

    on_exit(fn ->
      Application.put_env(:cozy_checkout, :abra_accommodation, previous)
      Req.default_options(options)
    end)

    billing_fixture()
  end

  test "accountant's advance payment updates the stay balance without creating payments or ZDD",
       %{booking: b, invoice: calc} do
    doc = issue_without_abra!(b, "advance", %{"amount" => "1000"})
    export = export!(doc, "101")
    expect_invoices([invoice(doc, export, "0")])
    assert :ok = PaymentStatus.sync(b.id)
    checked = Accommodation.get_export(doc.id)
    assert PaymentStatus.state(checked) == "paid"
    refute PaymentStatus.stale?(checked)
    account = BookingSummary.for_accounts(b.id)[doc.billing_account_id]
    assert account.payment_state == "partial"
    assert Decimal.equal?(account.outstanding, Decimal.sub(calc.total_price, 1000))
    assert Decimal.equal?(account.received, 1000)
    summary = BookingSummary.for_bookings([b.id])[b.id]
    assert summary.payment_state == "partial"
    assert Decimal.equal?(summary.outstanding, account.outstanding)
    assert summary.paid_count == 0

    assert {:ok, {[found], _}} =
             CozyCheckout.Bookings.list_bookings_with_flop(%{"invoice_state" => "partial"})

    assert found.id == b.id
    assert Repo.aggregate(Payment, :count) == 0
    assert Repo.aggregate(Document, :count) == 1
    assert Billing.get_document!(doc.id).pdf_sha256 == doc.pdf_sha256
    assert Billing.get_document!(doc.id).snapshot == doc.snapshot
  end

  test "partial payment and reversal both change the remaining balance", %{
    booking: b,
    invoice: calc
  } do
    doc = issue_without_abra!(b, "advance", %{"amount" => "1000"})
    export = export!(doc, "101")
    expect_invoices([invoice(doc, export, "600")])
    assert :ok = PaymentStatus.sync(b.id)
    assert PaymentStatus.state(Accommodation.get_export(doc.id)) == "partial"

    assert Decimal.equal?(
             BookingSummary.for_accounts(b.id)[doc.billing_account_id].outstanding,
             Decimal.sub(calc.total_price, 400)
           )

    expect_invoices([invoice(doc, export, "1000")])
    assert :ok = PaymentStatus.sync(b.id)
    assert PaymentStatus.state(Accommodation.get_export(doc.id)) == "unpaid"

    assert Decimal.equal?(
             BookingSummary.for_accounts(b.id)[doc.billing_account_id].outstanding,
             calc.total_price
           )
  end

  test "final balance already includes deductions; advances and local payments are not subtracted again",
       %{booking: b} do
    advance = issue_without_abra!(b, "advance", %{"amount" => "1000"})
    ae = export!(advance, "101")
    receipt!(b, "1000", %{"document_id" => advance.id})
    final = issue_without_abra!(b, "final")
    fe = export!(final, "102")
    expect_invoices([invoice(advance, ae, "0"), invoice(final, fe, "1200", "2000")])
    count = Repo.aggregate(Document, :count)
    assert :ok = PaymentStatus.sync(b.id)
    account = BookingSummary.for_accounts(b.id)[final.billing_account_id]
    assert Decimal.equal?(account.outstanding, 1200)
    assert account.payment_state == "partial"
    assert Repo.aggregate(Payment, :count) == 1
    assert Repo.aggregate(Document, :count) == count
    expect_invoices([invoice(advance, ae, "0"), invoice(final, fe, "0", "2000")])
    assert :ok = PaymentStatus.sync(b.id)
    assert BookingSummary.for_accounts(b.id)[final.billing_account_id].payment_state == "paid"
  end

  test "a fully deducted final invoice with zero total is paid", %{booking: b} do
    final = issue_without_abra!(b, "final")
    export = export!(final, "101")
    expect_invoices([invoice(final, export, "0", "0")])
    assert :ok = PaymentStatus.sync(b.id)
    assert PaymentStatus.state(Accommodation.get_export(final.id)) == "paid"

    assert Decimal.equal?(
             BookingSummary.for_accounts(b.id)[final.billing_account_id].outstanding,
             0
           )
  end

  test "failed and missing responses retain the last balance with a visible stale marker", %{
    booking: b
  } do
    doc = issue_without_abra!(b, "final")
    export = export!(doc, "101")
    expect_invoices([invoice(doc, export, "500")])
    assert :ok = PaymentStatus.sync(b.id)
    checked = Accommodation.get_export(doc.id)
    Req.Test.expect(Client, fn conn -> Plug.Conn.send_resp(conn, 503, "Unavailable") end)
    assert {:error, _} = PaymentStatus.sync(b.id)
    expect_invoices([])
    assert {:error, _} = PaymentStatus.sync(b.id)
    failed = Accommodation.get_export(doc.id)
    assert failed.payment_checked_at == checked.payment_checked_at
    assert Decimal.equal?(failed.payment_remaining, 500)
    assert failed.payment_error
    assert PaymentStatus.stale?(failed)
    assert BookingSummary.for_accounts(b.id)[doc.billing_account_id].abra_error
  end

  test "unverified invoices never become remotely paid", %{booking: b} do
    doc = issue_without_abra!(b, "final")
    export!(doc, "101")
    expect_invoices([])
    assert {:error, _} = PaymentStatus.sync(b.id)
    assert PaymentStatus.state(Accommodation.get_export(doc.id)) == nil
    assert BookingSummary.for_accounts(b.id)[doc.billing_account_id].abra_checked_at == nil
  end

  test "currency, identity, cancellation and malformed money cannot report a zero balance", %{
    booking: b
  } do
    doc = issue_without_abra!(b, "final")
    export = export!(doc, "101")

    for patch <- [
          %{"mena" => "code:EUR"},
          %{"kod" => "OTHER"},
          %{"varSym" => "OTHER"},
          %{"storno" => true},
          %{"storno" => nil},
          %{"zbyvaUhradit" => nil},
          %{"sumCelkem" => "NaN"},
          %{"zbyvaUhradit" => "0.001"},
          %{"id" => %{}}
        ] do
      expect_invoices([Map.merge(invoice(doc, export, "0"), patch)])
      assert {:error, _} = PaymentStatus.sync(b.id)
      assert Accommodation.get_export(doc.id).payment_checked_at == nil
    end
  end

  test "one missing advance prevents an incomplete account total", %{booking: b} do
    first = issue_without_abra!(b, "advance", %{"amount" => "1000"})
    second = issue_without_abra!(b, "advance", %{"amount" => "1000"})
    export = export!(first, "101")
    export!(second, "102")
    expect_invoices([invoice(first, export, "0")])
    assert {:error, _} = PaymentStatus.sync(b.id)
    assert BookingSummary.for_accounts(b.id)[first.billing_account_id].abra_checked_at == nil
    assert BookingSummary.for_bookings([b.id])[b.id].outstanding == nil
  end

  test "another company and deleted documents are excluded", %{booking: b} do
    doc = issue_without_abra!(b, "advance", %{"amount" => "1000"})
    export = export!(doc, "101")
    export |> Ecto.Changeset.change(company_id: "different-company") |> Repo.update!()
    assert :ok = PaymentStatus.sync(b.id)
    assert PaymentStatus.for_documents([doc]) == %{}
    export |> Ecto.Changeset.change(company_id: "payments-test") |> Repo.update!()
    doc |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()
    assert :ok = PaymentStatus.sync(b.id)
  end

  test "disabled integration never sends HTTP, while manual requests enqueue a scoped job", %{
    booking: b
  } do
    assert {:ok, _} = PaymentStatus.enqueue(b.id)
    assert_enqueued(worker: AbraPaymentStatusWorker, args: %{booking_id: b.id})

    Application.put_env(
      :cozy_checkout,
      :abra_accommodation,
      Keyword.put(Accommodation.config(), :enabled, false)
    )

    assert :ok = PaymentStatus.sync()
    assert {:error, _} = PaymentStatus.enqueue(b.id)
  end

  test "an old response cannot overwrite a newer observation", %{booking: b} do
    doc = issue_without_abra!(b, "final")
    export = export!(doc, "101")

    Req.Test.expect(Client, fn conn ->
      export
      |> Ecto.Changeset.change(
        payment_total: doc.total,
        payment_remaining: Decimal.new(500),
        payment_checked_at: DateTime.utc_now(),
        payment_attempted_at: DateTime.utc_now()
      )
      |> Repo.update!()

      Req.Test.json(conn, %{"winstrom" => %{"faktura-vydana" => [invoice(doc, export, "0")]}})
    end)

    assert :ok = PaymentStatus.sync(b.id)
    assert Decimal.equal?(Accommodation.get_export(doc.id).payment_remaining, 500)
  end

  test "separate payer balances aggregate without crossing payment scopes", %{booking: b} do
    {:ok, second_payer} = Billing.save_account(b.id, %{"name" => "Druhá rodina", "adults" => "1"})
    first = issue_without_abra!(b, "final")
    cfg = Accommodation.config()
    Application.put_env(:cozy_checkout, :abra_accommodation, Keyword.put(cfg, :enabled, false))

    second =
      try do
        {:ok, preview} = Billing.preview(second_payer, "final")

        {:ok, doc} =
          Billing.issue(
            second_payer,
            "final",
            %{"preview_token" => preview.token},
            Ecto.UUID.generate()
          )

        doc
      after
        Application.put_env(:cozy_checkout, :abra_accommodation, cfg)
      end

    e1 = export!(first, "101")
    e2 = export!(second, "102")
    expect_invoices([invoice(first, e1, "500"), invoice(second, e2, "700")])
    assert :ok = PaymentStatus.sync(b.id)
    accounts = BookingSummary.for_accounts(b.id)
    assert Decimal.equal?(accounts[first.billing_account_id].outstanding, 500)
    assert Decimal.equal?(accounts[second.billing_account_id].outstanding, 700)
    total = BookingSummary.for_bookings([b.id])[b.id]
    assert total.abra_account_count == 2
    assert total.payment_state == "partial"
    assert Decimal.equal?(total.outstanding, 1200)
    assert Repo.aggregate(Payment, :count) == 0
  end

  test "51 linked invoices use two bounded HTTP reads", %{booking: b} do
    first = issue_without_abra!(b, "advance", %{"amount" => "1000"})

    docs = [
      first
      | Enum.map(2..51, fn n ->
          attrs =
            first
            |> Map.from_struct()
            |> Map.drop([
              :__meta__,
              :id,
              :inserted_at,
              :updated_at,
              :booking,
              :billing_account,
              :parent
            ])
            |> Map.merge(%{
              number: "SYNC#{n}",
              variable_symbol: "990#{n}",
              request_id: Ecto.UUID.generate()
            })

          Repo.insert!(struct(Document, attrs))
        end)
    ]

    invoices =
      docs
      |> Enum.with_index(101)
      |> Map.new(fn {doc, id} ->
        export = export!(doc, to_string(id))
        {export.remote_id, invoice(doc, export, "1000")}
      end)

    for size <- [50, 1] do
      Req.Test.expect(Client, fn conn ->
        assert conn.method == "GET"
        [_, list] = Regex.run(~r/id in \(([0-9,]+)\)/, URI.decode(conn.request_path))
        ids = String.split(list, ",")
        assert length(ids) == size

        Req.Test.json(conn, %{
          "winstrom" => %{"faktura-vydana" => Enum.map(ids, &Map.fetch!(invoices, &1))}
        })
      end)
    end

    assert :ok = PaymentStatus.sync(b.id)

    assert Enum.all?(PaymentStatus.for_documents(docs), fn {_, export} ->
             not is_nil(export.payment_checked_at)
           end)
  end

  test "completed refresh jobs do not prevent future manual or scheduled refreshes", %{booking: b} do
    assert {:ok, first} = PaymentStatus.enqueue(b.id)

    first
    |> Ecto.Changeset.change(state: "completed", completed_at: DateTime.utc_now())
    |> Repo.update!()

    assert {:ok, second} = PaymentStatus.enqueue(b.id)
    assert second.id != first.id
  end

  test "updating an advance invalidates its previous payment observation", %{booking: b} do
    doc = issue_without_abra!(b, "advance", %{"amount" => "1000"})
    export = export!(doc, "101")
    expect_invoices([invoice(doc, export, "0")])
    assert :ok = PaymentStatus.sync(b.id)
    Accommodation.invalidate_advance!(doc)
    invalidated = Accommodation.get_export(doc.id)
    assert invalidated.state == "outdated"
    assert invalidated.payment_checked_at == nil
    assert invalidated.payment_remaining == nil
    assert PaymentStatus.for_documents([doc]) == %{}
  end

  defp export!(doc, remote_id) do
    Repo.insert!(%AccommodationExport{
      document_id: doc.id,
      base_url: "https://accounting.test",
      company_id: "payments-test",
      external_id: "ext:cozy-checkout:accommodation:#{doc.id}",
      remote_id: remote_id,
      state: "synced",
      payload: %{}
    })
  end

  defp invoice(doc, export, remaining, total \\ nil) do
    %{
      "id" => export.remote_id,
      "kod" => doc.number,
      "varSym" => doc.variable_symbol,
      "mena" => "code:CZK",
      "storno" => false,
      "sumCelkem" => total || to_string(doc.total),
      "zbyvaUhradit" => remaining
    }
  end

  defp expect_invoices(rows) do
    Req.Test.expect(Client, fn conn ->
      assert conn.method == "GET"
      assert URI.decode(conn.request_path) =~ "/c/payments-test/faktura-vydana/(id in ("
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["limit"] == "50"
      Req.Test.json(conn, %{"winstrom" => %{"faktura-vydana" => rows}})
    end)
  end
end
