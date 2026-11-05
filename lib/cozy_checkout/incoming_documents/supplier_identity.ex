defmodule CozyCheckout.IncomingDocuments.SupplierIdentity do
  @moduledoc "Strict source identity contract and conservative Czech registration matching."
  @fields ~w(name ic dic country_code)
  def schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => @fields ++ ~w(ambiguous uncertainties),
      "properties" =>
        Map.merge(Map.new(@fields, &{&1, %{"type" => ["string", "null"]}}), %{
          "ambiguous" => %{"type" => "boolean"},
          "uncertainties" => %{"type" => "array", "items" => %{"type" => "string"}}
        })
    }
  end

  def validate(data) when is_map(data) do
    if Enum.sort(Map.keys(data)) == Enum.sort(@fields ++ ~w(ambiguous uncertainties)) and
         Enum.all?(@fields, &(is_nil(data[&1]) or bounded?(data[&1]))) and
         is_boolean(data["ambiguous"]) and is_list(data["uncertainties"]) and
         length(data["uncertainties"]) <= 20 and Enum.all?(data["uncertainties"], &bounded?/1),
       do: :ok,
       else: {:error, "Neplatná struktura identity dodavatele"}
  end

  def validate(_), do: {:error, "Neplatná struktura identity dodavatele"}
  defp bounded?(s), do: is_binary(s) and byte_size(s) <= 2000

  def normalize(data) do
    Map.take(data, @fields)
    |> Map.update("ic", nil, &normalize_ic/1)
    |> Map.update("dic", nil, &normalize_dic/1)
    |> Map.update("country_code", nil, &country/1)
  end

  def normalize_ic(nil), do: nil

  def normalize_ic(s) when is_binary(s) do
    s
    |> String.trim()
    |> String.replace(~r/^I[ČC]O\s*:?\s*/iu, "")
    |> String.replace(~r/[ \t\r\n\x{00a0}\x{202f}]/u, "")
  end

  def normalize_dic(nil), do: nil

  def normalize_dic(s) when is_binary(s),
    do:
      s
      |> String.upcase()
      |> String.replace(~r/^DI[ČC]\s*:?\s*/u, "")
      |> String.replace(~r/\s/u, "")

  defp country(nil), do: nil
  defp country(s), do: s |> String.trim() |> String.upcase()

  def valid_ic?(s) when is_binary(s) do
    if Regex.match?(~r/^\d{8}$/, s) do
      digits = s |> String.to_charlist() |> Enum.map(&(&1 - ?0))

      sum =
        Enum.zip(Enum.take(digits, 7), 8..2//-1)
        |> Enum.reduce(0, fn {n, w}, acc -> acc + n * w end)

      rem(11 - rem(sum, 11), 10) == List.last(digits)
    else
      false
    end
  end

  def valid_ic?(_), do: false

  def conflict(identity, supplier) do
    actual = normalize(supplier)

    Enum.find_value(~w(ic dic), fn key ->
      if identity[key] not in [nil, ""] and actual[key] not in [nil, ""] and
           identity[key] != actual[key],
         do:
           "Vytěžené #{String.upcase(key)} se liší od zvolené identity. Zkontrolujte dodavatele proti originálu."
    end)
  end
end
