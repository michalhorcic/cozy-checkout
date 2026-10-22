defmodule CozyCheckout.BillingConcurrencyTest do
  use ExUnit.Case, async: false
  @moduletag :financial
  import Ecto.Query
  import CozyCheckout.BillingFixtures
  alias CozyCheckout.{Billing, Repo}
  alias CozyCheckout.Billing.{Document, Payment, Customer, Season, Profile, Series, Delivery}
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    # Register cleanup before committing any setup rows, including partial setup failures.
    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        guests =
          Repo.all(
            from g in CozyCheckout.Guests.Guest, where: g.name == "Host fakturace", select: g.id
          )

        bookings =
          Repo.all(
            from b in CozyCheckout.Bookings.Booking, where: b.guest_id in ^guests, select: b.id
          )

        invoices =
          Repo.all(
            from i in CozyCheckout.Bookings.BookingInvoice,
              where: i.booking_id in ^bookings,
              select: i.id
          )

        Repo.delete_all(from j in Oban.Job, where: j.queue == "billing")
        Repo.delete_all(Delivery)
        Repo.delete_all(Payment)
        Repo.delete_all(Document)
        Repo.delete_all(Customer)
        Repo.delete_all(Season)
        Repo.delete_all(Profile)
        Repo.delete_all(Series)

        Repo.delete_all(
          from i in CozyCheckout.Bookings.BookingInvoiceItem,
            where: i.booking_invoice_id in ^invoices
        )

        Repo.delete_all(from i in CozyCheckout.Bookings.BookingInvoice, where: i.id in ^invoices)
        Repo.delete_all(from b in CozyCheckout.Bookings.Booking, where: b.id in ^bookings)
        Repo.delete_all(from g in CozyCheckout.Guests.Guest, where: g.id in ^guests)
      end)
    end)

    Sandbox.unboxed_run(Repo, &billing_fixture/0)
  end

  test "separate connections issuing a final cannot duplicate it or consume two numbers", %{
    booking: booking
  } do
    {:ok, preview} = Sandbox.unboxed_run(Repo, fn -> Billing.preview(booking.id, "final") end)

    results =
      race([1, 2], fn _ ->
        Billing.issue(
          booking.id,
          "final",
          %{"preview_token" => preview.token},
          Ecto.UUID.generate()
        )
      end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1

    Sandbox.unboxed_run(Repo, fn ->
      assert Repo.aggregate(Document, :count) == 1
      assert Repo.get_by!(Series, kind: "final", year: Billing.today().year).next_number == 2
    end)
  end

  test "separate connections replaying a receipt create one payment and one tax document", %{
    booking: booking
  } do
    attrs = %{
      "request_id" => Ecto.UUID.generate(),
      "kind" => "receipt",
      "amount" => "1000",
      "paid_on" => to_string(Date.add(Billing.today(), -15)),
      "method" => "bank"
    }

    results = race([1, 2], fn _ -> Billing.record_payment(booking.id, attrs) end)
    assert Enum.all?(results, &match?({:ok, _}, &1))

    assert results |> Enum.map(fn {:ok, payment} -> payment.id end) |> Enum.uniq() |> length() ==
             1

    Sandbox.unboxed_run(Repo, fn ->
      assert Repo.aggregate(Payment, :count) == 1
      assert Repo.aggregate(Document, :count) == 1
    end)
  end

  defp race(inputs, fun) do
    parent = self()

    tasks =
      Enum.map(inputs, fn input ->
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            send(parent, {:ready, self()})

            receive do
              :go -> fun.(input)
            after
              5000 -> raise "start barrier timed out"
            end
          end)
        end)
      end)

    for _ <- tasks, do: assert_receive({:ready, _}, 5000)
    for task <- tasks, do: send(task.pid, :go)
    Task.await_many(tasks, 15_000)
  end
end
