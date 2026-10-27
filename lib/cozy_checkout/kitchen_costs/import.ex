defmodule CozyCheckout.KitchenCosts.Import do
  @moduledoc "Strict v1 receipt contract. Parsing never writes data or fetches external resources."
  alias CozyCheckout.KitchenCosts
  @units ~w(kg g l ml ks)
  @decimal ~r/^\d+(\.\d+)?$/

  def parse(json) when is_binary(json) and byte_size(json) <= 1_000_000 do
    with {:ok, data} <- Jason.decode(json),
         :ok <- validate(data) do
      receipt = data["receipt"]

      attrs =
        Map.take(receipt, ~w(merchant purchased_on document_number currency total_paid rounding))

      lines =
        Enum.map(data["items"], fn item ->
          id = item["proposed_ingredient_id"]

          Map.take(
            item,
            ~w(line_number source_name quantity unit package_count package_quantity package_unit)
          )
          |> Map.put("line_total", item["line_total_after_discount"])
          |> Map.put("ingredient_id", id)
          |> Map.put("classification", if(id, do: "ingredient", else: "unassigned"))
        end)

      {:ok,
       %{
         attrs:
           Map.merge(attrs, %{
             "import_id" => data["import_id"],
             "lines" => lines,
             "original_json" => data
           }),
         shared_discount: receipt["shared_discount"] || "0",
         warnings: data["warnings"],
         items: data["items"]
       }}
    else
      {:error, %Jason.DecodeError{}} -> {:error, "Neplatný JSON"}
      error -> error
    end
  end

  def parse(_), do: {:error, "JSON může mít nejvýše 1 MB"}

  defp validate(data) when is_map(data) do
    receipt = data["receipt"]
    items = data["items"]

    cond do
      not keys?(data, ~w(schema_version import_id receipt items warnings)) or
          not required?(data, ~w(schema_version import_id receipt items warnings)) ->
        invalid("Nepovolená pole importu")

      data["schema_version"] != 1 ->
        invalid("Nepodporovaná verze schématu")

      not uuid?(data["import_id"]) ->
        invalid("Chybí platné import_id")

      not strings?(data["warnings"]) ->
        invalid("warnings musí být seznam textů")

      not is_map(receipt) ->
        invalid("Chybí údaje dokladu")

      not required?(
        receipt,
        ~w(merchant purchased_on document_number currency total_paid rounding)
      ) ->
        invalid("Chybí pole dokladu; nejasné údaje uveďte jako null")

      not keys?(
        receipt,
        ~w(merchant purchased_on document_number currency total_paid rounding shared_discount)
      ) ->
        invalid("Nepovolená pole dokladu")

      not nullable_text?(receipt["merchant"]) or not nullable_text?(receipt["document_number"]) ->
        invalid("Obchod a číslo dokladu musí být text nebo null")

      not date?(receipt["purchased_on"]) ->
        invalid("Datum musí být ISO datum nebo null")

      receipt["currency"] != "CZK" ->
        invalid("Podporována je měna CZK")

      not amount?(receipt["total_paid"], true) or not signed_amount?(receipt["rounding"]) or
          not amount?(receipt["shared_discount"] || "0", false) ->
        invalid(
          "Částky musí být desetinné řetězce s nejvýše dvěma desetinnými místy, nejasné údaje null"
        )

      not is_list(items) or length(items) not in 1..500 ->
        invalid("Doklad musí mít 1–500 řádků")

      not Enum.all?(items, &item?/1) ->
        invalid(
          "Neplatný řádek: zkontrolujte typ zboží, desetinné řetězce, jednotky a návrh suroviny"
        )

      length(Enum.uniq_by(items, & &1["line_number"])) != length(items) ->
        invalid("Čísla řádků nejsou jedinečná")

      true ->
        :ok
    end
  end

  defp validate(_), do: invalid("Import musí být objekt")

  defp item?(item) when is_map(item) do
    required?(
      item,
      ~w(line_number source_name kind quantity unit line_total_after_discount proposed_ingredient_id proposed_ingredient_name mapping_reason warnings)
    ) and
      keys?(
        item,
        ~w(line_number source_name quantity unit kind package_count package_quantity package_unit line_total_after_discount proposed_ingredient_id proposed_ingredient_name mapping_reason warnings)
      ) and
      is_integer(item["line_number"]) and item["line_number"] > 0 and
      is_binary(item["source_name"]) and String.length(item["source_name"]) in 1..255 and
      item["kind"] in ~w(packaged weighed) and decimal?(item["quantity"], true) and
      item["unit"] in [nil | @units] and amount?(item["line_total_after_discount"], true) and
      (is_nil(item["proposed_ingredient_id"]) or uuid?(item["proposed_ingredient_id"])) and
      nullable_text?(item["proposed_ingredient_name"]) and nullable_text?(item["mapping_reason"]) and
      strings?(item["warnings"]) and packaging?(item)
  end

  defp item?(_), do: false

  defp packaging?(%{"kind" => "packaged"} = item),
    do:
      required?(item, ~w(package_count package_quantity package_unit)) and
        decimal?(item["package_count"], true) and decimal?(item["package_quantity"], true) and
        item["package_unit"] in [nil | @units]

  defp packaging?(item),
    do: Enum.all?(~w(package_count package_quantity package_unit), &is_nil(item[&1]))

  defp keys?(map, keys), do: Enum.all?(Map.keys(map), &(&1 in keys))
  defp required?(map, keys), do: Enum.all?(keys, &Map.has_key?(map, &1))
  defp nullable_text?(nil), do: true
  defp nullable_text?(v), do: is_binary(v) and byte_size(v) <= 1000

  defp strings?(v),
    do:
      is_list(v) and length(v) <= 100 and Enum.all?(v, &(is_binary(&1) and byte_size(&1) <= 2000))

  defp uuid?(v), do: match?({:ok, _}, Ecto.UUID.cast(v))
  defp date?(nil), do: true
  defp date?(v) when is_binary(v), do: match?({:ok, _}, Date.from_iso8601(v))
  defp date?(_), do: false
  defp decimal?(nil, nullable), do: nullable
  defp decimal?(v, _) when is_binary(v), do: byte_size(v) <= 40 and Regex.match?(@decimal, v)
  defp decimal?(_, _), do: false
  defp amount?(nil, nullable), do: nullable

  defp amount?(v, _) when is_binary(v),
    do: byte_size(v) <= 40 and Regex.match?(~r/^\d+(\.\d{1,2})?$/, v)

  defp amount?(_, _), do: false
  defp signed_amount?(nil), do: true

  defp signed_amount?(v) when is_binary(v),
    do: byte_size(v) <= 40 and Regex.match?(~r/^-?\d+(\.\d{1,2})?$/, v)

  defp signed_amount?(_), do: false
  defp invalid(message), do: {:error, message}

  def catalog do
    %{
      schema_version: 1,
      ingredients:
        Enum.map(
          CozyCheckout.Recipes.list_ingredients("", true),
          &Map.take(&1, [:id, :name, :base_unit, :archived_at])
        ),
      mappings:
        Enum.map(
          KitchenCosts.list_mappings(),
          &Map.take(&1, [:merchant_key, :source_key, :source_name, :ingredient_id, :lock_version])
        )
    }
  end

  @doc "Explicit proportional distribution in cents; the sum always equals the requested discount."
  def distribute_discount(lines, amount) do
    with true <- amount?(amount, false),
         {discount, ""} <- Decimal.parse(amount),
         true <-
           Decimal.compare(discount, 0) != :lt and
             Decimal.equal?(discount, Decimal.round(discount, 2)),
         {:ok, totals} <- line_totals(lines),
         total <- Enum.reduce(totals, Decimal.new(0), &Decimal.add/2),
         true <- Decimal.compare(total, 0) == :gt and Decimal.compare(discount, total) != :gt do
      cents = Decimal.mult(discount, 100) |> Decimal.to_integer()

      shares =
        Enum.map(
          totals,
          &(Decimal.mult(&1, cents)
            |> Decimal.div(total)
            |> Decimal.round(0, :floor)
            |> Decimal.to_integer())
        )

      remainder = cents - Enum.sum(shares)

      {shares, 0} =
        Enum.map_reduce(Enum.zip(shares, totals), remainder, fn {share, price}, left ->
          if left > 0 and Decimal.compare(price, Decimal.div(share, 100)) == :gt,
            do: {share + 1, left - 1},
            else: {share, left}
        end)

      {:ok,
       Enum.zip_with(lines, shares, fn line, share ->
         Map.put(
           line,
           "line_total",
           Decimal.sub(line["line_total"], Decimal.div(share, 100)) |> Decimal.to_string(:normal)
         )
       end)}
    else
      _ ->
        {:error,
         "Zadejte platnou slevu nejvýše do součtu položek a konečné ceny řádků na dvě desetinná místa"}
    end
  end

  defp line_totals(lines) do
    if Enum.all?(lines, &amount?(&1["line_total"], false)),
      do: {:ok, Enum.map(lines, &Decimal.new(&1["line_total"]))},
      else: :error
  end
end
