defmodule CozyCheckout.AbraBankTest do
  use CozyCheckout.DataCase, async: false
  @moduletag :financial
  import CozyCheckout.BillingFixtures
  alias CozyCheckout.Abra.{Accommodation, Bank, BankImport, BankMovement, Client}
  alias CozyCheckout.Billing.{Document, Payment}

  setup do
    old = Application.get_env(:cozy_checkout, :abra_accommodation)
    options = Req.default_options()

    Application.put_env(:cozy_checkout, :abra_accommodation,
      enabled: true,
      enabled_from: ~U[2020-01-01 00:00:00Z],
      base_url: "https://accounting.test",
      company_id: "bank-test",
      username: "test-user",
      password: "test-password",
      bank_account_code: "TEST"
    )

    Req.default_options(plug: {Req.Test, Client})
    Req.Test.verify_on_exit!()

    on_exit(fn ->
      Application.put_env(:cozy_checkout, :abra_accommodation, old)
      Req.default_options(options)
    end)

    fixture = billing_fixture()

    Map.put(
      fixture,
      :document,
      issue_without_abra!(fixture.booking, "advance", %{"amount" => "1234.57"})
    )
  end

  test "repeated reads update one identity and suggest a final invoice for the old advance VS without financial writes",
       %{booking: booking, document: doc} do
    movement = movement(1, doc.variable_symbol)
    expect_page([movement])
    assert :ok = Bank.sync()
    refute Map.has_key?(movement, "bankovniUcet")
    [first] = Bank.for_booking(booking.id)
    assert first.document.id == doc.id
    assert Decimal.equal?(first.difference, 0)

    final = issue_without_abra!(booking, "final")
    expect_page([Map.put(movement, "sumCelkem", "1300.00")])
    assert :ok = Bank.sync()
    [second] = Bank.for_booking(booking.id)
    assert second.movement.id == first.movement.id
    assert second.document.id == final.id
    assert Decimal.equal?(second.difference, Decimal.sub("1300", final.total))
    assert Repo.aggregate(BankMovement, :count) == 1
    assert Repo.aggregate(Payment, :count) == 0
    assert Repo.aggregate(Document, :count) == 2
    assert Bank.status().last_success_at
  end

  test "page retry preserves checkpoint; complete scan detects changes, missing rows and late older receipts",
       %{document: doc} do
    rows = for id <- 1..100, do: movement(id, doc.variable_symbol)
    expect_page(rows, 0)

    Req.Test.expect(Client, fn conn ->
      assert Plug.Conn.fetch_query_params(conn).query_params["start"] == "100"
      Req.Test.transport_error(conn, :timeout)
    end)

    assert {:error, _} = Bank.sync()
    assert Bank.status().offset == 100
    assert Bank.status().error
    refute Bank.status().last_success_at

    late = movement(101, doc.variable_symbol) |> Map.put("datVyst", "2020-01-01+01:00")
    expect_page([late], 100)
    assert :ok = Bank.sync()
    assert Repo.aggregate(BankMovement, :count) == 101
    assert Repo.get_by!(BankMovement, remote_id: "101").paid_on == ~D[2020-01-01]

    expect_page([Map.put(movement(1, doc.variable_symbol), "sparovano", true)], 0)
    assert :ok = Bank.sync()
    assert Repo.get_by!(BankMovement, remote_id: "2").missing_at
    assert Repo.get_by!(BankMovement, remote_id: "1").pairing == "paired"
    assert Enum.all?(Bank.list(), &is_nil(&1.document))
  end

  test "invalid movements stay without suggestions; paired candidates require verification",
       %{booking: booking, document: doc} do
    rows = [
      movement(1, doc.variable_symbol) |> Map.put("banka", "code:OTHER"),
      movement(2, doc.variable_symbol)
      |> Map.merge(%{"mena" => "code:EUR", "sumCelkemMen" => "50.00"}),
      movement(3, doc.variable_symbol) |> Map.put("typPohybuK", "typPohybu.vydej"),
      movement(4, doc.variable_symbol) |> Map.put("sparovano", true),
      movement(5, ""),
      movement(6, "unknown")
    ]

    expect_page(rows)
    assert :ok = Bank.sync()
    assert Repo.aggregate(BankMovement, :count) == 5

    assert Enum.all?(
             Enum.reject(Bank.list(), &(&1.movement.remote_id == "4")),
             &is_nil(&1.document)
           )

    assert Decimal.equal?(Repo.get_by!(BankMovement, remote_id: "2").amount, 50)
    assert [paired] = Bank.for_booking(booking.id)
    assert paired.document.id == doc.id
    assert paired.reason =~ "ověřte"

    Repo.update_all(from(b in CozyCheckout.Bookings.Booking, where: b.id == ^booking.id),
      set: [inserted_at: ~U[2019-01-01 00:00:00Z]]
    )

    expect_page([movement(7, doc.variable_symbol)])
    assert :ok = Bank.sync()
    assert Bank.for_booking(booking.id) == []
  end

  test "malformed page is atomic and cannot advance the checkpoint or last success; disabled import and changed targets are isolated",
       %{document: doc} do
    expect_page([movement(1, doc.variable_symbol)])
    assert :ok = Bank.sync()
    success = Bank.status().last_success_at
    expect_page([movement(2, doc.variable_symbol), %{"id" => 3}])
    assert {:error, reason} = Bank.sync()
    assert reason =~ "záznam 2, pole banka"
    assert Bank.status().error == reason
    assert Bank.status().offset == 0
    assert Bank.status().last_success_at == success
    assert Repo.aggregate(BankMovement, :count) == 1

    configure(enabled: false)
    assert :ok = Bank.sync()
    assert {:error, _} = Bank.enqueue()
    configure(enabled: true, company_id: "other-test")
    assert Bank.list() == []
    assert Bank.status() == nil
    assert Repo.aggregate(BankImport, :count) == 1
  end

  defp movement(id, symbol) do
    %{
      "id" => id,
      "banka" => "code:TEST",
      "sumCelkem" => "1234.57",
      "mena" => "code:CZK",
      "typPohybuK" => "typPohybu.prijem",
      "datVyst" => "2026-10-20+02:00",
      "varSym" => symbol,
      "nazFirmy" => "Host",
      "sparovano" => false
    }
  end

  defp expect_page(rows, offset \\ 0) do
    Req.Test.expect(Client, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/c/bank-test/banka.json"
      params = Plug.Conn.fetch_query_params(conn).query_params
      assert params["start"] == to_string(offset)
      assert params["limit"] == "100"
      Req.Test.json(conn, %{"winstrom" => %{"banka" => rows}})
    end)
  end

  defp configure(attrs),
    do:
      Application.put_env(
        :cozy_checkout,
        :abra_accommodation,
        Keyword.merge(Accommodation.config(), attrs)
      )
end
