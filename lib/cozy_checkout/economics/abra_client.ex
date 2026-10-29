defmodule CozyCheckout.Economics.AbraClient do
  @moduledoc "Bounded, GET-only ABRA reporting API. No accounting commands or arbitrary URLs."
  alias CozyCheckout.Economics.Config

  @page_size 1000
  @max_pages 100
  @movement_fields "idUcetniDenik,idDokl,modul,ucet,protiUcet,datUcto,sumTuzMd,sumTuzDal,zuctovano,mena"
  @balance_fields "ucet,ucetniObdobi,mena,pocatekMd,pocatekDal,pocatekMesic,obratMdVyb,obratDalVyb,zustatekMd,zustatekDal"
  @saldo_fields "idSaldoKdatu,idDokl,modul,datUcto,datSplat,sumCelkem,sumCelkemAkt,juhSumDat,mena,storno"

  def periods, do: fetch("ucetni-obdobi", "kod,platiOdData,platiDoData", [], "id")
  def accounts, do: fetch("ucet", "kod,nazev,typUctuK,druhUctuK", [], "id")

  def movements(%Date{} = first, %Date{} = last, state \\ "posted")
      when state in ["posted", "unposted"] do
    path = "pohyb-na-uctech/(datUcto >= #{first} and datUcto <= #{last})"
    fetch(path, @movement_fields, [postingState: state], ["idUcetniDenik", "ucet"])
  end

  def trial_balance(period, %Date{} = last, months) when is_integer(months) and months in 1..23 do
    fetch(
      "obratova-predvaha",
      @balance_fields,
      [
        ucetniObdobi: "code:" <> period,
        koncovyMesicRok: Calendar.strftime(last, "%m/%Y"),
        pocetMesicu: months
      ],
      "ucet"
    )
  end

  def open_items(%Date{} = date) do
    fetch(
      "saldo-k-datu",
      @saldo_fields,
      [datum: Date.to_iso8601(date), dleUcto: true],
      "idSaldoKdatu"
    )
  end

  defp fetch(path, fields, params, order) do
    with {:ok, cfg} <- Config.connection() do
      key = path |> String.split("/") |> hd()

      params =
        [detail: "custom:" <> fields] ++ Enum.map(List.wrap(order), &{:order, &1}) ++ params

      pages(cfg, path, key, params, 0, [], MapSet.new())
    end
  end

  defp pages(_cfg, _path, _key, _params, page, _acc, _seen) when page >= @max_pages,
    do: {:error, :page_limit}

  defp pages(cfg, path, key, params, page, acc, seen) do
    {base, company} = Config.identity(cfg)

    url =
      base <>
        "/c/" <>
        URI.encode(company, &URI.char_unreserved?/1) <> "/" <> URI.encode(path) <> ".json"

    case Req.get(url,
           params: params ++ [limit: @page_size, start: page * @page_size],
           auth: {:basic, cfg[:username] <> ":" <> cfg[:password]},
           redirect: false,
           retry: false,
           receive_timeout: 60_000,
           connect_options: [timeout: 10_000]
         ) do
      {:ok, %{status: 200, body: %{"winstrom" => %{^key => rows}}}} when is_list(rows) ->
        digest = :crypto.hash(:sha256, :erlang.term_to_binary(rows))

        cond do
          not Enum.all?(rows, &is_map/1) or length(rows) > @page_size ->
            {:error, :invalid_response}

          rows != [] and MapSet.member?(seen, digest) ->
            {:error, :repeated_page}

          length(rows) < @page_size ->
            {:ok, acc |> Enum.reverse() |> List.flatten() |> Kernel.++(rows)}

          true ->
            pages(cfg, path, key, params, page + 1, [rows | acc], MapSet.put(seen, digest))
        end

      {:ok, %{status: 200}} ->
        {:error, :invalid_response}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, _exception} ->
        {:error, :transport}
    end
  end
end
