defmodule CozyCheckout.Adventure.BillingTest do
  use CozyCheckout.DataCase, async: false

  import CozyCheckout.AdventureFixtures, only: [adventure_booking: 1]

  alias CozyCheckout.Adventure.Sources.Billing
  alias CozyCheckout.Billing.{Account, Document, Payment}
  alias CozyCheckout.Bookings.BookingInvoice
  alias CozyCheckout.QueryRecorder

  @campaign %{starts_on: ~D[2026-12-01], ends_on: ~D[2027-03-31]}
  @as_of ~U[2027-02-01 12:00:00Z]

  setup do
    previous = Application.get_env(:cozy_checkout, :adventure_enabled, false)
    Application.put_env(:cozy_checkout, :adventure_enabled, true)
    on_exit(fn -> Application.put_env(:cozy_checkout, :adventure_enabled, previous) end)
    :ok
  end

  test "disabled Adventure returns before any source query" do
    Application.put_env(:cozy_checkout, :adventure_enabled, false)
    {result, queries} = QueryRecorder.record(fn -> Billing.evaluate(@campaign, as_of: @as_of) end)
    assert result == {:error, :disabled}
    assert queries == []
  end

  test "30k advance plus 70k payment settles a 100k final without counting tax receipts or deductions" do
    account = account(booking())
    advance = document(account, "advance", "30000", %{issued_on: ~D[2026-11-01]})
    tax = document(account, "tax_receipt", "30000", %{issued_on: ~D[2026-11-15]})

    final =
      document(account, "final", "100000", %{
        snapshot: %{
          "customer" => %{"name" => "Private buyer", "email" => "private@example.test"},
          "deductions" => [%{"source_document_id" => tax.id, "gross" => "-30000"}]
        }
      })

    payment(account, "30000", ~D[2026-11-15], %{
      document_id: advance.id,
      tax_document_id: tax.id
    })

    payment(account, "70000", ~D[2027-01-10], %{document_id: final.id})

    {result, queries} = QueryRecorder.record(fn -> Billing.evaluate(@campaign, as_of: @as_of) end)

    assert length(queries) == 1
    assert_money(result, "period_receipts_amount", "70000")
    assert_money(result, "period_refunds_amount", "0")
    assert_money(result, "period_net_amount", "70000")
    assert_money(result, "settlement_billed_amount", "100000")
    assert_money(result, "settlement_paid_amount", "100000")
    assert_money(result, "settlement_remaining_amount", "0")
    assert_money(result, "settlement_overpayment_amount", "0")
    assert result["metrics"]["settlement_final_accounts_count"] == 1
    assert result["quality"]["completeness"] == "complete"
    assert result["source"] == "billing"
    assert result["definition_version"] == 1
    assert result["as_of"] == DateTime.to_iso8601(@as_of)
    assert Jason.encode!(result)
    refute inspect(result) =~ "Private"
    refute inspect(result) =~ "@example.test"
    refute inspect(result) =~ account.id
    refute Map.has_key?(result["metrics"], "overdue")
  end

  test "refunds and signed direct-final corrections affect settlement without counting other corrections" do
    account = account(booking())
    final = document(account, "final", "1000")
    correction = document(account, "correction", "-200", %{parent_id: final.id})
    document(account, "correction", "999", %{parent_id: correction.id})
    document(account, "correction", "50", %{parent_id: final.id})

    document(account, "correction", "500", %{
      parent_id: final.id,
      issued_on: ~D[2027-02-02]
    })

    advance = document(account, "advance", "300")
    document(account, "correction", "-300", %{parent_id: advance.id})
    tax = document(account, "tax_receipt", "300")
    document(account, "correction", "-300", %{parent_id: tax.id})
    payment(account, "1000", ~D[2027-01-10])
    payment(account, "200", ~D[2027-01-11], %{kind: "refund"})
    payment(account, "800", ~D[2027-02-02])

    result = Billing.evaluate(@campaign, as_of: @as_of)
    assert_money(result, "period_receipts_amount", "1000")
    assert_money(result, "period_refunds_amount", "200")
    assert_money(result, "period_net_amount", "800")
    assert_money(result, "settlement_billed_amount", "850")
    assert_money(result, "settlement_paid_amount", "800")
    assert_money(result, "settlement_remaining_amount", "50")
    assert_money(result, "settlement_overpayment_amount", "0")
  end

  test "multiple payers use the common booking departure and do not net overpayments against debt" do
    booking = booking()
    first = account(booking, %{check_out_date: ~D[2026-11-30]})
    second = account(booking, %{check_out_date: ~D[2027-04-01]})
    document(first, "final", "100")
    document(second, "final", "200")
    payment(first, "150", ~D[2027-01-10])
    payment(second, "100", ~D[2027-01-10])

    result = Billing.evaluate(@campaign, as_of: @as_of)
    assert result["metrics"]["settlement_bookings_count"] == 1
    assert result["metrics"]["settlement_accounts_count"] == 2
    assert_money(result, "settlement_billed_amount", "300")
    assert_money(result, "settlement_remaining_amount", "100")
    assert_money(result, "settlement_overpayment_amount", "50")
  end

  test "cancelled and deleted bookings and issued history on deleted accounts remain included" do
    deleted = account(booking(%{deleted_at: ~U[2027-01-20 12:00:00Z]}), %{deleted_at: @as_of})
    cancelled = account(booking(%{status: "cancelled"}))
    account(booking(%{check_out_date: ~D[2027-04-01]}))
    document(deleted, "final", "100")
    payment(deleted, "60", ~D[2027-01-10])
    document(cancelled, "final", "200")
    payment(cancelled, "220", ~D[2027-01-10])
    account(Repo.get!(CozyCheckout.Bookings.Booking, cancelled.booking_id), %{deleted_at: @as_of})

    result = Billing.evaluate(@campaign, as_of: @as_of)
    assert result["metrics"]["settlement_bookings_count"] == 2
    assert result["metrics"]["settlement_accounts_count"] == 2
    assert_money(result, "settlement_billed_amount", "300")
    assert_money(result, "settlement_paid_amount", "280")
    assert_money(result, "settlement_remaining_amount", "40")
    assert_money(result, "settlement_overpayment_amount", "20")
    assert result["quality"]["missing_final_accounts"] == 0
  end

  test "missing final, missing accounts and incomplete allocation are not verified zero amounts" do
    booking(%{allocation_completed_at: nil})
    missing = account(booking())
    payment(missing, "60", ~D[2027-01-10])
    personal = account(booking())

    Repo.insert!(%BookingInvoice{
      booking_id: personal.booking_id,
      billing_account_id: personal.id,
      state: "personal",
      total_price: Decimal.new("99999")
    })

    result = Billing.evaluate(@campaign, as_of: @as_of)
    assert result["metrics"]["personal_accounts_count"] == 1
    assert result["metrics"]["settlement_billed_amount"] == nil
    assert result["metrics"]["settlement_remaining_amount"] == nil
    assert result["metrics"]["settlement_overpayment_amount"] == nil
    assert_money(result, "settlement_paid_amount", "60")
    assert result["quality"]["missing_final_accounts"] == 1
    assert result["quality"]["personal_accounts_missing_final"] == 1
    assert result["quality"]["bookings_without_accounts"] == 1
    assert result["quality"]["incomplete_allocation_bookings"] == 1
    assert result["quality"]["completeness"] == "partial"
    assert result["quality"]["settlement_amounts_status"] == "unavailable"

    assert get_in(result, ["quality", "metrics", "settlement_billed_amount", "completeness"]) ==
             "unavailable"

    assert get_in(result, ["quality", "metrics", "period_net_amount", "completeness"]) ==
             "complete"

    assert get_in(result, ["quality", "metrics", "settlement_paid_amount", "completeness"]) ==
             "complete"
  end

  test "mixed missing-final cohort exposes known issued amounts with partial quality" do
    known = account(booking())
    unknown = account(booking())
    document(known, "final", "100")
    payment(unknown, "50", ~D[2027-01-10])
    result = Billing.evaluate(@campaign, as_of: @as_of)
    assert_money(result, "settlement_billed_amount", "100")
    assert_money(result, "settlement_paid_amount", "50")
    assert_money(result, "settlement_remaining_amount", "100")
    assert_money(result, "settlement_overpayment_amount", "0")
    assert result["quality"]["settlement_amounts_status"] == "partial"
    assert result["quality"]["missing_final_accounts"] == 1
    assert result["evidence"]["settlement_amounts_scope"] == "accounts_with_final"
  end

  test "missing departure preserves period cash but cannot claim a complete empty settlement" do
    unknown = account(booking(%{check_out_date: nil}))
    document(unknown, "final", "1000")
    document(unknown, "advance", "30")
    payment(unknown, "30", ~D[2027-01-10])
    payment(unknown, "10", ~D[2027-01-11], %{kind: "refund"})

    {result, queries} = QueryRecorder.record(fn -> Billing.evaluate(@campaign, as_of: @as_of) end)

    assert length(queries) == 1
    assert result["quality"]["uncertain_departure_bookings"] == 1
    assert result["quality"]["completeness"] == "partial"
    assert result["quality"]["settlement_amounts_status"] == "unavailable"
    assert result["metrics"]["settlement_bookings_count"] == 0
    assert result["metrics"]["settlement_final_accounts_count"] == 0

    for key <- [
          "settlement_billed_amount",
          "settlement_paid_amount",
          "settlement_remaining_amount",
          "settlement_overpayment_amount"
        ] do
      assert result["metrics"][key] == nil
      assert get_in(result, ["quality", "metrics", key, "completeness"]) == "unavailable"
    end

    assert_money(result, "period_receipts_amount", "30")
    assert_money(result, "period_refunds_amount", "10")
    assert_money(result, "period_net_amount", "20")

    assert get_in(result, ["quality", "metrics", "period_net_amount", "completeness"]) ==
             "complete"
  end

  test "missing and reversed stay dates mark a mixed cohort partial without inventing amounts" do
    known = account(booking())
    document(known, "final", "100")
    payment(known, "40", ~D[2027-01-10])

    for dates <- [
          %{check_out_date: nil},
          %{check_in_date: ~D[2027-01-20], check_out_date: ~D[2027-01-10]}
        ] do
      unknown = account(booking(dates))
      document(unknown, "final", "1000")
      payment(unknown, "5", ~D[2027-01-10])
    end

    {result, queries} = QueryRecorder.record(fn -> Billing.evaluate(@campaign, as_of: @as_of) end)
    assert length(queries) == 1
    assert result["quality"]["uncertain_departure_bookings"] == 2
    assert result["quality"]["settlement_amounts_status"] == "partial"
    assert result["metrics"]["settlement_bookings_count"] == 1
    assert result["metrics"]["settlement_final_accounts_count"] == 1
    assert_money(result, "settlement_billed_amount", "100")
    assert_money(result, "settlement_paid_amount", "40")
    assert_money(result, "settlement_remaining_amount", "60")
    assert_money(result, "period_net_amount", "50")

    for key <- ["settlement_billed_amount", "settlement_paid_amount", "settlement_bookings_count"] do
      assert get_in(result, ["quality", "metrics", key, "completeness"]) == "partial"
    end
  end

  test "same-day stay retains issued final and payment in the departure cohort" do
    same_day =
      account(booking(%{check_in_date: ~D[2027-01-10], check_out_date: ~D[2027-01-10]}))

    document(same_day, "final", "100")
    payment(same_day, "40", ~D[2027-01-10])

    {result, queries} = QueryRecorder.record(fn -> Billing.evaluate(@campaign, as_of: @as_of) end)
    assert length(queries) == 1
    assert result["quality"]["uncertain_departure_bookings"] == 0
    assert result["quality"]["completeness"] == "complete"
    assert result["quality"]["settlement_amounts_status"] == "complete"
    assert result["metrics"]["settlement_bookings_count"] == 1
    assert result["metrics"]["settlement_final_accounts_count"] == 1
    assert_money(result, "settlement_billed_amount", "100")
    assert_money(result, "settlement_paid_amount", "40")
    assert_money(result, "settlement_remaining_amount", "60")
    assert_money(result, "period_net_amount", "40")
  end

  test "unrelated undated bookings are not assigned to a season without dated evidence" do
    outside = account(booking(%{check_in_date: ~D[2026-11-01], check_out_date: nil}))
    document(outside, "final", "1000", %{issued_on: ~D[2026-11-01]})
    payment(outside, "30", ~D[2026-11-02])
    booking(%{check_in_date: ~D[2027-04-01], check_out_date: nil})
    empty = Billing.evaluate(@campaign, as_of: @as_of)
    assert empty["quality"]["uncertain_departure_bookings"] == 0
    assert empty["quality"]["completeness"] == "complete"
    assert_money(empty, "settlement_billed_amount", "0")

    payment(outside, "5", ~D[2027-01-10])
    related = Billing.evaluate(@campaign, as_of: @as_of)
    assert related["quality"]["uncertain_departure_bookings"] == 1
    assert related["metrics"]["settlement_billed_amount"] == nil
    assert_money(related, "period_net_amount", "5")
  end

  test "cash flow is independent of departure cohort and settlement includes post-season payments" do
    campaign = %{starts_on: ~D[2026-12-01], ends_on: ~D[2027-01-31], closed_at: @as_of}
    inside = account(booking(%{check_in_date: ~D[2026-11-28]}))
    outside = account(booking(%{check_out_date: ~D[2027-04-02]}))
    document(inside, "final", "100")
    document(outside, "final", "500")
    payment(inside, "30", ~D[2026-11-30])
    payment(inside, "70", ~D[2027-02-01])
    payment(inside, "20", ~D[2027-02-02], %{kind: "refund"})
    payment(outside, "500", ~D[2027-01-31])
    payment(outside, "10", ~D[2026-12-01], %{kind: "refund"})
    result = Billing.evaluate(campaign, as_of: ~U[2027-02-03 12:00:00Z])

    assert_money(result, "period_receipts_amount", "500")
    assert_money(result, "period_refunds_amount", "10")
    assert_money(result, "period_net_amount", "490")
    assert_money(result, "settlement_billed_amount", "100")
    assert_money(result, "settlement_paid_amount", "80")
    assert_money(result, "settlement_remaining_amount", "20")
    assert result["metrics"]["settlement_bookings_count"] == 1
  end

  test "Prague as_of date inclusively caps payment dates, departure dates and issued dates" do
    campaign = %{starts_on: ~D[2027-01-01], ends_on: ~D[2027-01-31]}
    first = account(booking(%{check_out_date: ~D[2027-01-10]}))
    second = account(booking(%{check_out_date: ~D[2027-01-11]}))
    document(first, "final", "100", %{issued_on: ~D[2027-01-11]})
    document(second, "final", "200", %{issued_on: ~D[2027-01-11]})
    payment(first, "100", ~D[2027-01-11])

    before_midnight = Billing.evaluate(campaign, as_of: ~U[2027-01-10 22:59:59Z])
    assert before_midnight["metrics"]["settlement_bookings_count"] == 1
    assert before_midnight["metrics"]["settlement_billed_amount"] == nil
    assert_money(before_midnight, "period_net_amount", "0")

    after_midnight = Billing.evaluate(campaign, as_of: ~U[2027-01-10 23:00:00Z])
    assert after_midnight["metrics"]["settlement_bookings_count"] == 2
    assert_money(after_midnight, "settlement_billed_amount", "300")
    assert_money(after_midnight, "period_net_amount", "100")
    assert after_midnight["evidence"]["as_of_on"] == "2027-01-11"
  end

  test "empty and larger cohorts both use exactly one read query" do
    {empty, empty_queries} =
      QueryRecorder.record(fn -> Billing.evaluate(@campaign, as_of: @as_of) end)

    assert_money(empty, "settlement_billed_amount", "0")
    assert empty["quality"]["completeness"] == "complete"

    for _ <- 1..12 do
      account = account(booking())
      final = document(account, "final", "100")
      document(account, "correction", "-10", %{parent_id: final.id})
      payment(account, "20", ~D[2026-11-30])
      payment(account, "70", ~D[2027-01-10])
    end

    {result, queries} = QueryRecorder.record(fn -> Billing.evaluate(@campaign, as_of: @as_of) end)
    assert length(empty_queries) == 1
    assert length(queries) == 1
    assert result["metrics"]["settlement_accounts_count"] == 12
    assert_money(result, "settlement_billed_amount", "1080")
    assert_money(result, "settlement_paid_amount", "1080")
    assert_money(result, "settlement_remaining_amount", "0")
  end

  test "departure cohort includes both campaign boundary dates and excludes adjacent departures" do
    campaign = %{starts_on: ~D[2027-01-10], ends_on: ~D[2027-01-11]}

    for departure <- [~D[2027-01-09], ~D[2027-01-10], ~D[2027-01-11], ~D[2027-01-12]] do
      account = account(booking(%{check_out_date: departure}))
      document(account, "final", "100")
    end

    result = Billing.evaluate(campaign, as_of: @as_of)
    assert result["metrics"]["settlement_bookings_count"] == 2
    assert_money(result, "settlement_billed_amount", "200")

    future = Billing.evaluate(campaign, as_of: ~U[2027-01-08 12:00:00Z])
    assert future["metrics"]["settlement_bookings_count"] == 0
    assert_money(future, "period_net_amount", "0")
    assert_money(future, "settlement_billed_amount", "0")
  end

  defp booking(attrs \\ %{}) do
    adventure_booking(
      Map.merge(
        %{
          check_in_date: ~D[2027-01-01],
          check_out_date: ~D[2027-01-10],
          allocation_completed_at: ~U[2027-01-01 12:00:00Z]
        },
        attrs
      )
    )
  end

  defp account(booking, attrs \\ %{}) do
    Repo.insert!(
      struct(Account, Map.merge(%{booking_id: booking.id, name: "Private payer"}, attrs))
    )
  end

  defp document(account, kind, amount, attrs \\ %{}) do
    Repo.insert!(
      struct(
        Document,
        Map.merge(
          %{
            booking_id: account.booking_id,
            billing_account_id: account.id,
            kind: kind,
            number: Ecto.UUID.generate(),
            variable_symbol: Ecto.UUID.generate(),
            request_id: Ecto.UUID.generate(),
            issued_on: ~D[2027-01-10],
            tax_date: ~D[2027-01-10],
            due_on: ~D[2027-01-24],
            snapshot: %{},
            total: Decimal.new(amount)
          },
          attrs
        )
      )
    )
  end

  defp payment(account, amount, date, attrs \\ %{}) do
    Repo.insert!(
      struct(
        Payment,
        Map.merge(
          %{
            booking_id: account.booking_id,
            billing_account_id: account.id,
            amount: Decimal.new(amount),
            paid_on: date,
            method: "bank",
            request_id: Ecto.UUID.generate()
          },
          attrs
        )
      )
    )
  end

  defp assert_money(result, key, expected) do
    assert is_binary(result["metrics"][key])
    assert Decimal.equal?(Decimal.new(result["metrics"][key]), Decimal.new(expected))
  end
end
