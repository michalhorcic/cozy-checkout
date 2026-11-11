defmodule CozyCheckout.Adventure.XpTransactionTest do
  use ExUnit.Case, async: true
  alias CozyCheckout.Adventure.XpTransaction

  defp attrs(amount) do
    %{
      profile_id: Ecto.UUID.generate(),
      quest_id: Ecto.UUID.generate(),
      award_key: "quest:test",
      amount: amount,
      reason: "Dokončení questu"
    }
  end

  test "zero and negative awards are rejected before insertion" do
    for amount <- [0, -50] do
      changeset = XpTransaction.award_changeset(attrs(amount))
      refute changeset.valid?
      assert {_, validation} = changeset.errors[:amount]
      assert validation[:validation] == :number
      assert validation[:kind] == :greater_than
    end
  end

  test "positive award is recorded as a change and attributed to the selected profile" do
    changeset = XpTransaction.award_changeset(attrs(250))
    assert changeset.valid?
    assert changeset.changes.amount == 250
    award = Ecto.Changeset.apply_changes(changeset)
    assert award.attribution == "self_selected"
    assert award.recipient_type == "profile"
  end

  test "missing and malformed XP cannot produce a valid award" do
    for amount <- [nil, "invalid"] do
      changeset = XpTransaction.award_changeset(attrs(amount))
      refute changeset.valid?
      assert changeset.errors[:amount]
    end
  end
end
