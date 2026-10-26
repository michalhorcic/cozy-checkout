defmodule CozyCheckout.Abra.FinalInvoiceVerification do
  @moduledoc "Strict read-back of final invoice amounts, ordinary lines, deduction lines and source bindings."
  alias CozyCheckout.Abra.BankVerification

  @doc "Verify an exact intermediate state and identify only fully applied source deductions."
  def progress(invoice, metadata, snapshot) do
    with {:ok, applied} <- binding_sources(snapshot, metadata["sources"]) do
      pending = Enum.reject(metadata["sources"], &(&1 in applied))

      expected =
        Enum.reduce(pending, metadata["expected"], fn source, totals ->
          Map.new(totals, fn {key, value} ->
            addition =
              cond do
                key in ["sumCelkem", "zbyvaUhradit"] -> source["gross"]
                key == "juhSum" -> "0"
                true -> source["totals"][key]
              end

            {key, to_string(Decimal.add(value, addition))}
          end)
        end)

      stage = metadata |> Map.put("sources", applied) |> Map.put("expected", expected)
      with :ok <- check(invoice, stage, snapshot), do: {:ok, applied}
    end
  end

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
        case binding_sources(snapshot, metadata["sources"]) do
          {:ok, applied} ->
            if applied == metadata["sources"],
              do: [],
              else: ["vazby na zdrojové ZDD (chybějící odpočet)"]

          {:error, reason} ->
            [reason]
        end

    if fields == [],
      do: :ok,
      else: {:error, "Faktura neprošla kontrolou: #{Enum.join(fields, ", ")}. Nic se nepřepisuje"}
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

  # ABRA binds each deduction ITEM (a) to the source ZDD header (b).
  # castka on the binding is not the monetary value of the deducted items.
  # https://podpora.flexibee.eu/cs/articles/3422294-cerpani-zdd-rest-api
  defp binding_sources(snapshot, sources) do
    deductions = Enum.filter(snapshot.items, &(&1["typPolozkyK"] == "typPolozky.odpocetZdd"))
    rows = Map.new(deductions, &{to_string(&1["id"]), &1})
    source_ids = Enum.map(sources, & &1["remote_id"])
    # Source ZDDs also have bank bindings and may be deducted on other invoices.
    # Select only deductions pointing at an item of THIS final invoice. The
    # existing coverage check still requires a proven binding for every item.
    from_sources =
      Enum.filter(Map.get(snapshot, :source_bindings, []), fn binding ->
        binding["typVazbyK"] == "typVazbyDokl.odpocetZDD" and
          case reference(binding["a@ref"]) do
            {_, "faktura-vydana-polozka", id} -> Map.has_key?(rows, id)
            _ -> false
          end
      end)

    bindings = Enum.uniq(snapshot.amounts ++ from_sources)

    with :ok <-
           require_binding(
             map_size(rows) == length(deductions) and Enum.all?(Map.keys(rows), &valid_id?/1),
             "chybějící nebo duplicitní ID odpočtové položky"
           ),
         :ok <-
           require_binding(
             Enum.all?(bindings, &valid_storno?/1),
             "neznámý stav storna vazby"
           ),
         active = Enum.filter(bindings, &active?/1),
         :ok <-
           require_binding(
             Enum.all?(active, &valid_id?(to_string(&1["id"]))) and
               length(Enum.uniq_by(active, &to_string(&1["id"]))) == length(active),
             "chybějící nebo duplicitní ID vazby"
           ),
         {:ok, grouped, used} <- linked_rows(active, rows, source_ids),
         :ok <-
           require_binding(
             MapSet.new(Map.keys(rows)) == used,
             "odpočtová položka nemá vazbu na ZDD; ID položek: " <>
               Enum.join(
                 Enum.sort(MapSet.to_list(MapSet.difference(MapSet.new(Map.keys(rows)), used))),
                 ", "
               )
           ),
         applied = Enum.filter(sources, &Map.has_key?(grouped, &1["remote_id"])),
         :ok <-
           require_binding(
             Enum.all?(applied, &deduction_totals(grouped[&1["remote_id"]], [&1])),
             "položky jednotlivého ZDD neodpovídají původním základům a DPH"
           ),
         :ok <-
           require_binding(
             graph_matches?(snapshot, applied),
             "graf dokladů neodpovídá ověřeným vazbám položek"
           ) do
      {:ok, applied}
    else
      {:error, detail} -> {:error, "vazby na zdrojové ZDD (#{detail})"}
    end
  end

  defp linked_rows(bindings, rows, source_ids) do
    Enum.reduce_while(bindings, {:ok, %{}, MapSet.new()}, fn binding, {:ok, grouped, used} ->
      with "typVazbyDokl.odpocetZDD" <- binding["typVazbyK"],
           {company, "faktura-vydana-polozka", item_id} <- reference(binding["a@ref"]),
           {^company, "faktura-vydana", source_id} <- reference(binding["b@ref"]),
           true <- source_id in source_ids,
           %{} = row <- rows[item_id],
           true <- active?(row),
           false <- MapSet.member?(used, item_id),
           true <- internal_id_matches?(binding, "a", item_id),
           true <- internal_id_matches?(binding, "b", source_id) do
        {:cont,
         {:ok, Map.update(grouped, source_id, [row], &[row | &1]), MapSet.put(used, item_id)}}
      else
        _ ->
          {:halt,
           {:error,
            "vazba ID #{binding["id"]}: neplatné a@ref/b@ref, zdroj, typ nebo opakované přiřazení položky"}}
      end
    end)
  end

  defp reference(ref) when is_binary(ref) do
    case URI.parse(ref).path do
      path when is_binary(path) ->
        segments = path |> URI.decode() |> String.split("/", trim: true)

        segments =
          case segments do
            ["v2" | rest] -> rest
            rest -> rest
          end

        case segments do
          ["c", company, evidence, id] ->
            id = String.replace(id, ~r/\.(json|xml)$/, "")
            if valid_id?(id), do: {company, evidence, id}

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp reference(_), do: nil

  defp internal_id_matches?(binding, side, id) do
    case binding[side <> "@internalId"] do
      nil -> true
      internal_id -> to_string(internal_id) == id
    end
  end

  defp graph_matches?(snapshot, applied) do
    links =
      Enum.reject(snapshot.links, fn row ->
        to_string(row["idDokl"]) == to_string(snapshot.invoice["id"]) and
          row["modulK"] == "modulUcetni.FAV" and row["typVazbyK"] in [nil, ""] and
          row["idVazby"] in [nil, "", 0, "0", -1, "-1"]
      end)

    direct = Enum.filter(links, &(active?(&1) and to_string(&1["uroven"]) == "1"))
    expected_ids = MapSet.new(applied, & &1["remote_id"])

    Enum.all?(links, &valid_storno?/1) and
      Enum.all?(
        direct,
        &(&1["modulK"] == "modulUcetni.FAV" and
            &1["typVazbyK"] == "typVazbyDokl.odpocetZDD")
      ) and
      MapSet.new(direct, &to_string(&1["idDokl"])) == expected_ids
  end

  defp require_binding(true, _detail), do: :ok
  defp require_binding(_, detail), do: {:error, detail}

  defp valid_id?(id), do: is_binary(id) and Regex.match?(~r/^[1-9][0-9]*$/, id)
  defp active?(row), do: row["storno"] in [false, "false"]
  defp valid_storno?(row), do: is_map(row) and row["storno"] in [true, false, "true", "false"]
end
