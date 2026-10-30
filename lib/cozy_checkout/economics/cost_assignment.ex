defmodule CozyCheckout.Economics.CostAssignment do
  @moduledoc false
  import Ecto.Changeset

  def validate(changeset) do
    changeset
    |> update_change(:reason, fn reason -> if reason, do: String.trim(reason) end)
    |> validate_required([:account, :behavior, :extraordinary])
    |> validate_inclusion(:behavior, ["fixed", "variable", "mixed", "unclassified"])
    |> validate_length(:reason, max: 1000)
    |> validate_length(:account, min: 1, max: 100)
    |> require_estimate_reason()
    |> validate_number(:fixed_percent, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_change(:fixed_percent, fn :fixed_percent, percent ->
      cond do
        get_field(changeset, :behavior) != "mixed" ->
          [fixed_percent: "Podíl patří pouze smíšenému nákladu."]

        Decimal.scale(percent) > 6 ->
          [fixed_percent: "Nejvýše šest desetinných míst."]

        true ->
          []
      end
    end)
  end

  defp require_estimate_reason(changeset) do
    if get_field(changeset, :behavior) == "mixed" and
         not is_nil(get_field(changeset, :fixed_percent)),
       do: validate_required(changeset, [:reason]),
       else: changeset
  end

  def first_month(changeset, field) do
    validate_change(changeset, field, fn field, date ->
      if date.day == 1, do: [], else: [{field, "Zvolte první den měsíce."}]
    end)
  end
end
