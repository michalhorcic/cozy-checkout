defmodule CozyCheckout.Economics.Reports do
  @moduledoc "Strict, pure accounting normalization and exact Decimal reconciliation."
  alias CozyCheckout.Economics.AccountMapping
  @zero Decimal.new(0)

  def period(row) do
    first = date!(row["platiOdData"])
    last = date!(row["platiDoData"])

    if first.day != 1 or Date.end_of_month(last) != last or Date.compare(first, last) == :gt,
      do: throw(:invalid_period)

    %{"code" => text!(row["kod"]), "from" => to_string(first), "to" => to_string(last)}
  end

  def periods(rows) do
    safely(fn ->
      periods = Enum.map(rows, &period/1)

      if length(Enum.uniq_by(periods, & &1["code"])) != length(periods),
        do: throw(:duplicate_period)

      Enum.sort_by(periods, & &1["from"])
    end)
  end

  def month(period, first, last, catalog, posted, unposted, trial, saldo) do
    safely(fn ->
      accounts = Map.new(catalog, &{text!(&1["kod"]), &1})
      if map_size(accounts) != length(catalog), do: throw(:duplicate_account)
      movements = Enum.map(posted, &movement!(&1, first, last, accounts, true)) |> Enum.sort()

      Enum.each(unposted, &filter!(&1, first, last, false))

      preliminary =
        case safely(fn ->
               Enum.map(unposted, &movement!(&1, first, last, accounts, false)) |> Enum.sort()
             end) do
          {:ok, rows} -> rows
          {:error, _} -> nil
        end

      balances = Enum.map(trial, &balance!(&1, period, accounts)) |> Enum.sort_by(& &1["account"])

      if length(Enum.uniq_by(balances, & &1["account"])) != length(balances),
        do: throw(:duplicate_balance)

      reconcile!(movements, balances)
      totals = totals(movements)

      open_items =
        Enum.map(saldo, &open_item!(&1, last)) |> Enum.sort_by(&{&1["module"], &1["document_id"]})

      if length(Enum.uniq_by(open_items, &{&1["module"], &1["document_id"]})) !=
           length(open_items),
         do: throw(:duplicate_open_item)

      open_items =
        Enum.reject(
          open_items,
          &(not is_nil(&1["amount"]) and Decimal.equal?(number!(&1["amount"]), 0))
        )

      warnings = []

      warnings =
        if Enum.any?(movements ++ (preliminary || []), &(&1["currency"] == "")),
          do: ["missing_currency" | warnings],
          else: warnings

      warnings = if unposted != [], do: ["unposted_documents" | warnings], else: warnings
      warnings = if is_nil(preliminary), do: ["unposted_incomplete" | warnings], else: warnings

      warnings =
        if Enum.any?(
             movements,
             &(&1["category"] == "Nezařazeno" and &1["kind"] in ["expense", "revenue"])
           ), do: ["unmapped_accounts" | warnings], else: warnings

      warnings =
        if Enum.any?(open_items, &is_nil(&1["amount"])),
          do: ["unsupported_open_items" | warnings],
          else: warnings

      %{
        "from" => to_string(first),
        "to" => to_string(last),
        "totals" => totals,
        "preliminary_totals" => if(preliminary, do: totals(preliminary)),
        "unposted_count" => length(unposted),
        "movements" => movements,
        "balances" => balances,
        "open_items" => open_items,
        "warnings" => Enum.sort(warnings),
        "mapping_version" => AccountMapping.version()
      }
    end)
  end

  def fingerprint(value),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(value)) |> Base.encode16(case: :lower)

  def totals(rows) do
    values =
      Enum.reduce(rows, %{revenue: @zero, expense: @zero, sales: @zero}, fn row, acc ->
        case row["kind"] do
          "revenue" ->
            amount = Decimal.sub(number!(row["dal"]), number!(row["md"]))
            acc = Map.update!(acc, :revenue, &Decimal.add(&1, amount))

            if AccountMapping.sales?(row["account"]),
              do: Map.update!(acc, :sales, &Decimal.add(&1, amount)),
              else: acc

          "expense" ->
            Map.update!(
              acc,
              :expense,
              &Decimal.add(&1, Decimal.sub(number!(row["md"]), number!(row["dal"])))
            )

          _ ->
            acc
        end
      end)

    values
    |> Map.put(:result, Decimal.sub(values.revenue, values.expense))
    |> Map.put(:other_revenue, Decimal.sub(values.revenue, values.sales))
    |> Map.new(fn {k, v} -> {to_string(k), string(v)} end)
  end

  def number!(value) when is_binary(value) or is_integer(value) do
    case Decimal.parse(to_string(value)) do
      {%Decimal{coef: coefficient} = decimal, ""} when is_integer(coefficient) -> decimal
      _ -> throw(:invalid_amount)
    end
  end

  def number!(_), do: throw(:invalid_amount)

  def date!(value) when is_binary(value) do
    if not Regex.match?(~r/^\d{4}-\d{2}-\d{2}(?:[+-]\d{2}:\d{2})?$/, value),
      do: throw(:invalid_date)

    case Date.from_iso8601(String.slice(value, 0, 10)) do
      {:ok, date} -> date
      _ -> throw(:invalid_date)
    end
  end

  def date!(_), do: throw(:invalid_date)

  defp filter!(row, first, last, posted?) do
    date = date!(row["datUcto"])

    if Date.compare(date, first) == :lt or Date.compare(date, last) == :gt,
      do: throw(:ignored_date_filter)

    if row["zuctovano"] not in [posted?, to_string(posted?)], do: throw(:ignored_posting_filter)
    date
  end

  defp movement!(row, first, last, catalog, posted?) do
    date = filter!(row, first, last, posted?)
    code = reference!(row["ucet"])
    account = account!(catalog, code)
    currency = currency!(row["mena"], true)

    %{
      "account" => code,
      "name" => text!(account["nazev"]),
      "kind" => kind!(account),
      "category" => AccountMapping.category(code),
      "date" => to_string(date),
      "md" => row["sumTuzMd"] |> number!() |> string(),
      "dal" => row["sumTuzDal"] |> number!() |> string(),
      "currency" => currency,
      "journal_id" => text!(row["idUcetniDenik"]),
      "document_id" => text!(row["idDokl"]),
      "module" => text!(row["modul"])
    }
  end

  defp balance!(row, period, catalog) do
    if reference!(row["ucetniObdobi"]) != period["code"], do: throw(:ignored_period_filter)
    currency!(row["mena"], false)
    code = reference!(row["ucet"])
    account = account!(catalog, code)
    md = number!(row["obratMdVyb"])
    dal = number!(row["obratDalVyb"])
    opening = Decimal.sub(number!(row["pocatekMd"]), number!(row["pocatekDal"]))
    closing = Decimal.sub(number!(row["zustatekMd"]), number!(row["zustatekDal"]))

    if not Decimal.equal?(Decimal.add(opening, Decimal.sub(md, dal)), closing),
      do: throw(:invalid_balance)

    %{
      "account" => code,
      "name" => text!(account["nazev"]),
      "kind" => kind!(account),
      "md" => string(md),
      "dal" => string(dal),
      "opening" => string(opening),
      "closing" => string(closing)
    }
  end

  defp reconcile!(movements, balances) do
    actual = Enum.group_by(movements, & &1["account"])
    expected = Map.new(balances, &{&1["account"], &1})

    for code <- Enum.uniq(Map.keys(actual) ++ Map.keys(expected)) do
      rows = Map.get(actual, code, [])
      balance = Map.get(expected, code, %{"md" => "0", "dal" => "0"})

      for side <- ["md", "dal"] do
        sum = Enum.reduce(rows, @zero, &Decimal.add(number!(&1[side]), &2))
        if not Decimal.equal?(sum, number!(balance[side])), do: throw(:trial_balance_mismatch)
      end
    end
  end

  defp open_item!(row, date) do
    currency!(row["mena"], false)
    booked = date!(row["datUcto"])
    if Date.compare(booked, date) == :gt, do: throw(:ignored_saldo_date)
    module = text!(row["modul"])
    if module not in ["FAV", "PHL", "FAP", "ZAV"], do: throw(:unknown_saldo_module)
    if row["storno"] not in [false, "false"], do: throw(:unsupported_saldo_cancellation)
    total = number!(row["sumCelkem"])
    current = number!(row["sumCelkemAkt"])
    paid = number!(row["juhSumDat"])
    # Differing document values need an independently verified historical correction contract.
    amount = if Decimal.equal?(total, current), do: string(Decimal.sub(total, paid)), else: nil
    due = if row["datSplat"] in [nil, ""], do: nil, else: to_string(date!(row["datSplat"]))

    %{
      "module" => module,
      "document_id" => text!(row["idDokl"]),
      "date" => to_string(booked),
      "due" => due,
      "amount" => amount,
      "kind" => if(module in ["FAV", "PHL"], do: "receivable", else: "payable")
    }
  end

  defp account!(catalog, code) do
    case Map.fetch(catalog, code) do
      {:ok, account} -> account
      _ -> throw(:unknown_account)
    end
  end

  defp kind!(%{"typUctuK" => "typUctu.vysledkovy", "druhUctuK" => kind}) do
    case kind do
      "druhUctu.naklady" -> "expense"
      "druhUctu.vynosy" -> "revenue"
      _ -> throw(:unknown_account_type)
    end
  end

  defp kind!(%{"typUctuK" => type})
       when type in ["typUctu.rozvahovy", "typUctu.podrozvahovy", "typUctu.zaverkovy"],
       do: "other"

  defp kind!(_), do: throw(:unknown_account_type)

  defp currency!("code:CZK", _), do: "CZK"
  defp currency!("", true), do: ""
  defp currency!(_, _), do: throw(:unsupported_currency)
  defp reference!("code:" <> value), do: text!(value)
  defp reference!(_), do: throw(:invalid_reference)
  defp text!(value) when is_integer(value), do: to_string(value)
  defp text!(value) when is_binary(value) and byte_size(value) > 0, do: value
  defp text!(_), do: throw(:missing_field)
  defp string(decimal), do: Decimal.to_string(decimal, :normal)

  defp safely(fun) do
    {:ok, fun.()}
  catch
    reason when is_atom(reason) -> {:error, reason}
  end
end
