defmodule CozyCheckout.Abra.FinalInvoiceVerification do
  @moduledoc "Strict read-back of trial invoice amounts, ordinary lines, deduction lines and source bindings."
  alias CozyCheckout.Abra.BankVerification

  def check(invoice, metadata, snapshot) do
    remote = snapshot.invoice
    exact = ~w(kod varSym typDokl mena bankovniUcet clenDph clenKonVykDph)

    buyer =
      Enum.filter(
        ~w(nazFirmy ulice mesto psc ic dic kontaktEmail stat),
        &Map.has_key?(invoice, &1)
      )

    dates = ~w(datVyst datSplat duzpPuv datUcto)

    fields =
      Enum.reject(exact ++ buyer, &(invoice[&1] == remote[&1])) ++
        Enum.reject(
          dates,
          &(is_binary(remote[&1]) and String.slice(remote[&1], 0, 10) == invoice[&1])
        ) ++
        (metadata["expected"]
         |> Enum.reject(fn {key, value} ->
           BankVerification.equal?(remote[key], Decimal.new(value))
         end)
         |> Enum.map(&elem(&1, 0))) ++
        if(remote["ucetni"] in [true, "true"], do: [], else: ["ucetni"]) ++
        if(remote["bezPolozek"] in [false, "false"], do: [], else: ["bezPolozek"]) ++
        if remote["storno"] in [false, "false"], do: [], else: ["storno"]

    fields =
      fields ++
        if(
          (is_integer(remote["id"]) and remote["id"] > 0) or
            (is_binary(remote["id"]) and remote["id"] != ""),
          do: [],
          else: ["id"]
        )

    {deductions, ordinary} =
      Enum.split_with(snapshot.items, &(&1["typPolozkyK"] == "typPolozky.odpocetZdd"))

    fields =
      fields ++
        if(
          Enum.sort(Enum.map(ordinary, &signature/1)) ==
            Enum.sort(Enum.map(invoice["polozkyFaktury"], &signature/1)),
          do: [],
          else: ["polozkyFaktury (ceny, DPH nebo účty)"]
        )

    fields =
      fields ++
        if(deduction_totals(deductions, metadata["sources"]),
          do: [],
          else: ["odpočty (původní základy nebo DPH)"]
        )

    fields =
      fields ++
        if(bindings?(snapshot, metadata["sources"]), do: [], else: ["vazby na zdrojové ZDD"])

    if fields == [],
      do: :ok,
      else:
        {:error,
         "Zkušební faktura neprošla kontrolou: #{Enum.join(fields, ", ")}. Nic se nepřepisuje"}
  end

  defp signature(row) do
    {Enum.map(~w(nazev zklDalUcet typSzbDphK typCenyDphK clenDph clenKonVykDph), &row[&1]),
     Enum.map(~w(mnozMj cenaMj sumZkl sumDph sumCelkem szbDph), &BankVerification.amount(row[&1]))}
  end

  defp deduction_totals(rows, sources) do
    initial =
      Map.new(
        ~w(sumOsv sumZklSniz sumDphSniz sumZklZakl sumDphZakl sumZklSniz2 sumDphSniz2),
        &{&1, Decimal.new(0)}
      )

    expected =
      Enum.reduce(sources, initial, fn source, sums ->
        Map.new(sums, fn {key, value} -> {key, Decimal.sub(value, source["totals"][key])} end)
      end)

    actual =
      Enum.reduce_while(rows, initial, fn row, sums ->
        keys =
          case row["typSzbDphK"] do
            "typSzbDph.dphSniz" -> {"sumZklSniz", "sumDphSniz"}
            "typSzbDph.dphZakl" -> {"sumZklZakl", "sumDphZakl"}
            "typSzbDph.dphOsv" -> {"sumOsv", nil}
            _ -> nil
          end

        net = BankVerification.amount(row["sumZkl"])
        vat = BankVerification.amount(row["sumDph"])
        gross = BankVerification.amount(row["sumCelkem"])

        if keys && net && vat && gross && Decimal.equal?(Decimal.add(net, vat), gross) do
          {net_key, vat_key} = keys
          sums = Map.update!(sums, net_key, &Decimal.add(&1, net))
          sums = if vat_key, do: Map.update!(sums, vat_key, &Decimal.add(&1, vat)), else: sums
          if is_nil(vat_key) and not Decimal.equal?(vat, 0), do: {:halt, nil}, else: {:cont, sums}
        else
          {:halt, nil}
        end
      end)

    not is_nil(actual) and
      Enum.all?(expected, fn {key, value} -> Decimal.equal?(actual[key], value) end)
  end

  defp bindings?(snapshot, sources) do
    active? = fn row -> row["storno"] in [false, "false"] end
    valid? = fn row -> is_map(row) and row["storno"] in [true, false, "true", "false"] end

    links =
      Enum.reject(snapshot.links, fn row ->
        to_string(row["idDokl"]) == to_string(snapshot.invoice["id"]) and
          row["modulK"] == "modulUcetni.FAV" and
          row["typVazbyK"] in [nil, ""] and row["idVazby"] in [nil, "", 0, "0", -1, "-1"]
      end)

    if Enum.all?(links ++ snapshot.amounts, valid?) do
      direct = Enum.filter(links, &(active?.(&1) and to_string(&1["uroven"]) == "1"))
      amounts = Enum.filter(snapshot.amounts, active?)

      length(direct) == length(sources) and length(amounts) == length(sources) and
        Enum.all?(sources, fn source ->
          matches =
            Enum.filter(
              direct,
              &(to_string(&1["idDokl"]) == source["remote_id"] and
                  &1["modulK"] == "modulUcetni.FAV" and
                  &1["typVazbyK"] == "typVazbyDokl.odpocetZDD")
            )

          case matches do
            [link] ->
              amount = Enum.find(amounts, &(to_string(&1["id"]) == to_string(link["idVazby"])))
              value = if amount, do: BankVerification.amount(amount["castka"])

              amount && amount["typVazbyK"] == "typVazbyDokl.odpocetZDD" && value &&
                Decimal.equal?(Decimal.abs(value), Decimal.new(source["gross"]))

            _ ->
              false
          end
        end)
    else
      false
    end
  end
end
