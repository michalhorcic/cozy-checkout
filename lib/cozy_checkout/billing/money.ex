defmodule CozyCheckout.Billing.Money do
  import Kernel, except: [round: 1]
  @moduledoc "Haléřové výpočty dokladů. Uložené řádky obsahují desetinná čísla jako řetězce."
  def decimal(%Decimal{} = n), do: n
  def decimal(n) when is_integer(n), do: Decimal.new(n)
  def decimal(n) when is_binary(n), do: Decimal.new(n)
  def round(n), do: Decimal.round(n, 2, :half_up)
  def sum(values), do: Enum.reduce(values, Decimal.new(0), &Decimal.add/2)
  def value(line, key), do: decimal(Map.fetch!(line, key))
  def total(lines), do: lines |> Enum.map(&value(&1, "gross")) |> sum()

  def line(name, quantity, nights, unit, rate, mode \\ "taxable", basis \\ "gross") do
    amount = unit |> decimal() |> Decimal.mult(decimal(quantity)) |> Decimal.mult(decimal(nights))
    rate = decimal(rate)

    {net, gross} =
      cond do
        mode == "outside" ->
          {round(amount), round(amount)}

        basis == "gross" ->
          gross = round(amount)
          {round(Decimal.div(gross, Decimal.add(1, Decimal.div(rate, 100)))), gross}

        true ->
          net = round(amount)
          {net, Decimal.add(net, round(Decimal.mult(net, Decimal.div(rate, 100))))}
      end

    %{
      "name" => name,
      "quantity" => to_string(quantity),
      "nights" => nights,
      "unit" => to_string(unit),
      "basis" => basis,
      "vat_rate" => to_string(rate),
      "tax_mode" => mode,
      "net" => to_string(net),
      "vat" => to_string(Decimal.sub(gross, net)),
      "gross" => to_string(gross)
    }
  end

  def groups(lines) do
    lines
    |> Enum.group_by(&{&1["tax_mode"], &1["vat_rate"]})
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {{mode, rate}, group} ->
      %{
        "name" => "Souhrn",
        "quantity" => "1",
        "nights" => 1,
        "unit" => to_string(total(group)),
        "basis" => "gross",
        "tax_mode" => mode,
        "vat_rate" => rate,
        "net" => to_string(sum(Enum.map(group, &value(&1, "net")))),
        "vat" => to_string(sum(Enum.map(group, &value(&1, "vat")))),
        "gross" => to_string(total(group))
      }
    end)
  end

  # Largest-remainder allocation keeps every tax group nonnegative even when a
  # tiny receipt is distributed across more groups than there are paid haléře.
  def allocate(lines, amount) do
    groups = groups(lines) |> Enum.filter(&Decimal.gt?(value(&1, "gross"), 0))
    total = total(groups)

    portions =
      Enum.with_index(groups)
      |> Enum.map(fn {group, index} ->
        exact = Decimal.div(Decimal.mult(amount, value(group, "gross")), total)
        floor = Decimal.round(exact, 2, :floor)
        %{group: group, index: index, floor: floor, remainder: Decimal.sub(exact, floor)}
      end)

    remaining =
      Decimal.sub(amount, sum(Enum.map(portions, & &1.floor)))
      |> Decimal.mult(100)
      |> Decimal.to_integer()

    winners =
      portions
      |> Enum.sort(fn left, right -> Decimal.compare(left.remainder, right.remainder) != :lt end)
      |> Enum.take(remaining)
      |> MapSet.new(& &1.index)

    Enum.map(portions, fn part ->
      share =
        if MapSet.member?(winners, part.index),
          do: Decimal.add(part.floor, Decimal.new("0.01")),
          else: part.floor

      line("Přijatá záloha", 1, 1, share, part.group["vat_rate"], part.group["tax_mode"])
    end)
  end

  def negate(line, label) do
    Enum.reduce(["net", "vat", "gross", "unit"], Map.put(line, "name", label), fn key, acc ->
      Map.put(acc, key, to_string(Decimal.negate(value(line, key))))
    end)
  end

  def credit(lines, amount) do
    groups = groups(lines) |> Enum.filter(&Decimal.gt?(value(&1, "gross"), 0))
    allocated = allocate(groups, amount)

    Enum.zip(groups, allocated)
    |> Enum.map(fn {original, part} ->
      # Full reversal must preserve the original rounded net and VAT exactly.
      part =
        if Decimal.equal?(value(original, "gross"), value(part, "gross")),
          do: original,
          else: part

      negate(part, "Oprava: snížení ceny")
    end)
  end
end
