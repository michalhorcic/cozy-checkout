defmodule CozyCheckout.AccountStampsTest do
  use CozyCheckout.DataCase, async: true

  import CozyCheckout.SalesFixtures

  alias CozyCheckout.{Repo, Sales}
  alias CozyCheckout.Sales.{AccountStamps, Order}

  test "new accounts prefer unused stamps and keep their stamp when renamed" do
    first = order_fixture()
    second = order_fixture()
    assert first.account_stamp in AccountStamps.keys()
    assert second.account_stamp in AccountStamps.keys()
    refute first.account_stamp == second.account_stamp

    {:ok, renamed} = Sales.update_order(first, %{"name" => "Renamed"})
    assert renamed.account_stamp == first.account_stamp
    assert Sales.get_order!(first.id).account_stamp == first.account_stamp
  end

  test "explicit choice is persisted and unrecognized stamps are rejected" do
    chosen = order_fixture(%{"account_stamp" => "lantern"})
    assert AccountStamps.key(Sales.get_order!(chosen.id)) == "lantern"

    assert {:error, changeset} =
             Sales.create_standalone_order(%{"name" => "Invalid", "account_stamp" => "../bad"})

    assert errors_on(changeset).account_stamp == ["is invalid"]
  end

  test "paid, cancelled and deleted accounts do not occupy suggestions" do
    order_fixture(%{"account_stamp" => "fox", "status" => "paid"})
    order_fixture(%{"account_stamp" => "fox", "status" => "cancelled"})
    deleted = order_fixture(%{"account_stamp" => "fox"})
    {:ok, _} = Sales.delete_order(deleted)
    assert Sales.suggest_account_stamp() == "fox"

    order_fixture(%{"account_stamp" => "fox", "status" => "partially_paid"})
    refute Sales.suggest_account_stamp() == "fox"
  end

  test "legacy stamps are stable across renames and count towards suggestions" do
    order = order_fixture()
    legacy = Ecto.Changeset.change(order, account_stamp: nil) |> Repo.update!()
    key = AccountStamps.key(legacy)
    assert key in AccountStamps.keys()

    {:ok, renamed} = Sales.update_order(legacy, %{"name" => "A different name"})
    assert AccountStamps.key(renamed) == key
    assert renamed.account_stamp == nil
    refute Sales.suggest_account_stamp() == key
  end

  test "after all eight stamps are used, suggestion chooses a least-used one" do
    Enum.each(AccountStamps.keys(), &order_fixture(%{"account_stamp" => &1}))
    order_fixture(%{"account_stamp" => "fox"})
    refute Sales.suggest_account_stamp() == "fox"
    assert Sales.suggest_account_stamp() in AccountStamps.keys()
    assert length(Repo.all(Order)) == 9
  end
end
