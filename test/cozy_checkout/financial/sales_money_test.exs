defmodule CozyCheckout.SalesMoneyTest do
  use CozyCheckout.DataCase, async: true
  @moduletag :financial
  import CozyCheckout.SalesFixtures
  alias CozyCheckout.Sales

  test "recalculation includes discount and tips and ignores deleted items" do
    order = order_fixture(%{"discount_amount" => "30", "tips_amount" => "20"})
    item_fixture(order, "300")
    deleted = item_fixture(order, "50")
    assert {:ok, _} = Sales.delete_order_item(deleted)
    assert {:ok, updated} = Sales.recalculate_order_total(order)
    assert_amount(updated.total_amount, "290")
    assert {:ok, again} = Sales.recalculate_order_total(updated)
    assert_amount(again.total_amount, "290")
  end

  test "payment status follows active payments and their deletion" do
    order = order_fixture()
    item_fixture(order, "300")
    assert {:ok, first} = Sales.create_payment(payment_attrs(order, "100"))
    assert Sales.get_order!(order.id).status == "partially_paid"
    assert {:ok, second} = Sales.create_payment(payment_attrs(order, "200", "qr_code"))
    assert Sales.get_order!(order.id).status == "paid"
    assert {:ok, _} = Sales.delete_payment(second)
    assert Sales.get_order!(order.id).status == "partially_paid"
    assert {:ok, _} = Sales.delete_payment(first)
    assert Sales.get_order!(order.id).status == "open"
  end

  test "overpayment is rejected" do
    order = order_fixture()
    item_fixture(order)
    assert {:error, _} = Sales.create_payment(payment_attrs(order, "100.01"))
  end

  test "a paid order cannot be paid a second time through the context" do
    order = order_fixture()
    item_fixture(order)
    assert {:ok, _} = Sales.create_payment(payment_attrs(order, "100"))
    assert {:error, _} = Sales.create_payment(payment_attrs(order, "100"))
  end

  test "cancelled orders cannot receive a payment" do
    order = order_fixture(%{"status" => "cancelled"})
    item_fixture(order)
    assert {:error, _} = Sales.create_payment(payment_attrs(order, "100"))
  end

  @tag :known_bug
  test "recalculation updates payment status when the outstanding total changes" do
    order = order_fixture()
    item_fixture(order, "300")
    {:ok, _} = Sales.create_payment(payment_attrs(order, "100"))

    {:ok, discounted} =
      Sales.update_order(Sales.get_order!(order.id), %{"discount_amount" => "200"})

    assert {:ok, updated} = Sales.recalculate_order_total(discounted)
    assert updated.status == "paid"
  end

  test "historical price and VAT survive changes to the pricelist" do
    order = order_fixture()
    {product, pricelist} = product_fixture("60", "12")
    attrs = %{"order_id" => order.id, "product_id" => product.id, "quantity" => "2"}
    {:ok, first} = Sales.create_order_item(attrs)
    {:ok, _} = CozyCheckout.Catalog.update_pricelist(pricelist, %{price: "70", vat_rate: "21"})
    {:ok, second} = Sales.create_order_item(attrs)
    assert_amount(Repo.reload!(first).unit_price, "60")
    assert_amount(Repo.reload!(first).vat_rate, "12")
    assert_amount(second.unit_price, "70")
    assert_amount(second.vat_rate, "21")
  end

  for amount <- ["0", "-1", "1.001", "10abc", "100000000", "NaN", "Infinity"] do
    if amount in ["1.001", "100000000"] do
      @tag :known_bug
    end

    test "invalid monetary input #{amount} is rejected without creating a payment" do
      order = order_fixture()
      item_fixture(order)
      assert {:error, _} = Sales.create_payment(payment_attrs(order, unquote(amount)))
      assert Sales.list_payments_for_order(order.id) == []
    end
  end

  test "deleting a payment does not allow its document number to be reused" do
    order = order_fixture()
    item_fixture(order)
    {:ok, first} = Sales.create_payment(payment_attrs(order, "50"))
    {:ok, _} = Sales.delete_payment(first)
    {:ok, second} = Sales.create_payment(payment_attrs(order, "50"))
    assert first.invoice_number != second.invoice_number
  end

  test "only the transition to paid enqueues an ABRA sync" do
    order = order_fixture()
    item_fixture(order)
    {:ok, _} = Sales.create_payment(payment_attrs(order, "50"))

    assert Repo.aggregate(
             from(j in Oban.Job, where: fragment("?->>'order_id'", j.args) == ^order.id),
             :count
           ) == 0

    {:ok, _} = Sales.create_payment(payment_attrs(order, "50"))

    assert Repo.aggregate(
             from(j in Oban.Job, where: fragment("?->>'order_id'", j.args) == ^order.id),
             :count
           ) == 1
  end

  @tag :known_bug
  test "missing prices cannot be replaced by caller supplied amounts" do
    order = order_fixture()
    {:ok, product} = CozyCheckout.Catalog.create_product(%{name: "Unpriced"})

    assert {:error, _} =
             Sales.create_order_item(%{
               "order_id" => order.id,
               "product_id" => product.id,
               "quantity" => "1",
               "unit_price" => "1",
               "vat_rate" => "0",
               "subtotal" => "1"
             })
  end

  @tag :known_bug
  test "changing unit price recalculates subtotal rather than trusting the caller" do
    order = order_fixture()
    item = item_fixture(order, "50", "21", 2)

    assert {:ok, updated} =
             Sales.update_order_item(item, %{"unit_price" => "60", "subtotal" => "1"})

    assert_amount(updated.subtotal, "120")
  end
end
