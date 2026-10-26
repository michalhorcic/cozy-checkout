defmodule CozyCheckout.Abra.Bank do
  @moduledoc "Read-only bank mirror and provisional VS suggestions. Never records payments."
  import Ecto.Query
  alias CozyCheckout.{Billing, Repo}
  alias CozyCheckout.Abra.{Accommodation, BankImport, BankMovement, Client}
  alias CozyCheckout.Billing.Document
  alias CozyCheckout.Bookings.Booking
  alias CozyCheckout.Workers.AbraBankWorker

  @page_size 100
  def enabled?, do: Accommodation.config()[:bank_enabled] == true

  def enqueue do
    if configured?() do
      %{} |> AbraBankWorker.new() |> Oban.insert()
    else
      {:error, "Načítání banky není zapnuté nebo chybí konfigurace"}
    end
  end

  def status do
    cfg = Accommodation.config()
    Repo.get_by(BankImport, target(cfg))
  end

  # Each page and its checkpoint commit together. HTTP stays outside transactions.
  # The row lock/checkpoint comparison also tolerates overlapping manual/cron jobs.
  def sync do
    if configured?() do
      cfg = Accommodation.config()
      state = begin_scan(cfg)
      import_pages(state, cfg, 20)
    else
      :ok
    end
  end

  defp begin_scan(cfg) do
    {:ok, state} =
      Repo.transaction(fn ->
        %BankImport{}
        |> Ecto.Changeset.change(target(cfg))
        |> Repo.insert!(
          on_conflict: :nothing,
          conflict_target: [:base_url, :company_id, :account]
        )

        state = Repo.one!(from s in BankImport, where: ^target(cfg), lock: "FOR UPDATE")

        state
        |> Ecto.Changeset.change(
          scan_id: state.scan_id || Ecto.UUID.generate(),
          last_attempt_at: DateTime.utc_now(:second),
          error: nil
        )
        |> Repo.update!()
      end)

    state
  end

  defp import_pages(_state, _cfg, 0), do: {:snooze, 1}

  defp import_pages(state, cfg, budget) do
    with {:ok, rows} <- Client.bank_page(state.offset, @page_size, cfg),
         {:ok, parsed} <- parse_rows(rows, state, cfg),
         {:ok, next} <- save_page(state, parsed, length(rows) < @page_size) do
      if is_nil(next.scan_id), do: :ok, else: import_pages(next, cfg, budget - 1)
    else
      {:error, :superseded} ->
        :ok

      {:error, reason} ->
        # Do not let a late failure overwrite a newer successful checkpoint.
        Repo.update_all(
          from(s in BankImport,
            where: s.id == ^state.id and s.scan_id == ^state.scan_id and s.offset == ^state.offset
          ),
          set: [error: to_string(reason)]
        )

        {:error, reason}
    end
  end

  defp save_page(state, rows, complete?) do
    Repo.transaction(fn ->
      current = Repo.one!(from s in BankImport, where: s.id == ^state.id, lock: "FOR UPDATE")

      if current.scan_id != state.scan_id or current.offset != state.offset,
        do: Repo.rollback(:superseded)

      for attrs <- rows do
        %BankMovement{}
        |> Ecto.Changeset.change(attrs)
        |> Repo.insert!(
          on_conflict: {:replace, Map.keys(attrs) ++ [:updated_at]},
          conflict_target: [:base_url, :company_id, :evidence, :remote_id]
        )
      end

      changes =
        if complete? do
          Repo.update_all(
            from(m in BankMovement,
              where:
                ^[base_url: state.base_url, company_id: state.company_id, account: state.account],
              where: m.scan_id != ^state.scan_id and is_nil(m.missing_at)
            ),
            set: [missing_at: DateTime.utc_now(:second)]
          )

          [scan_id: nil, offset: 0, last_success_at: DateTime.utc_now(:second), error: nil]
        else
          [offset: state.offset + @page_size]
        end

      current |> Ecto.Changeset.change(changes) |> Repo.update!()
    end)
  end

  defp parse_rows(rows, state, cfg) do
    rows
    |> Enum.with_index(state.offset + 1)
    |> Enum.reduce_while({:ok, []}, fn {row, index}, {:ok, acc} ->
      case parse(row, state, cfg) do
        {:ok, attrs} ->
          {:cont, {:ok, [attrs | acc]}}

        :skip ->
          {:cont, {:ok, acc}}

        {:error, field} ->
          {:halt,
           {:error,
            "Neplatný bankovní pohyb (záznam #{index}, pole #{field}); bod pokračování nebyl posunut"}}
      end
    end)
  end

  defp parse(row, state, cfg) when is_map(row) do
    if row["banka"] != "code:#{cfg[:bank_account_code]}" and is_binary(row["banka"]) do
      :skip
    else
      parse_movement(row, state, cfg)
    end
  end

  defp parse(_, _, _), do: {:error, "záznam"}

  defp parse_movement(row, state, cfg) do
    amount_field = if row["mena"] == "code:CZK", do: "sumCelkem", else: "sumCelkemMen"

    with {:ok, id} <-
           field(row, "id", &((is_integer(&1) and &1 > 0) or (is_binary(&1) and &1 != ""))),
         {:ok, account} <- field(row, "banka", &is_binary/1),
         {:ok, currency} <- field(row, "mena", &is_binary/1),
         {:ok, amount} <- movement_amount(row, amount_field),
         {:ok, date} <- field(row, "datVyst", &is_binary/1),
         {:ok, paid_on} <- movement_date(date),
         {:ok, direction} <- field(row, "typPohybuK", &is_binary/1),
         {:ok, symbol} <- field(row, "varSym", &(is_nil(&1) or is_binary(&1))),
         {:ok, counterparty} <- field(row, "nazFirmy", &(is_nil(&1) or is_binary(&1))),
         {:ok, description} <- field(row, "popis", &(is_nil(&1) or is_binary(&1))) do
      {:ok,
       %{
         base_url: cfg[:base_url],
         company_id: cfg[:company_id],
         evidence: "banka",
         remote_id: to_string(id),
         account: account,
         amount: amount,
         currency: currency,
         direction: direction,
         paid_on: paid_on,
         variable_symbol: symbol,
         counterparty: counterparty || description,
         raw: row,
         pairing: if(row["sparovano"] in [true, "true"], do: "paired", else: "unverified"),
         scan_id: state.scan_id,
         missing_at: nil
       }}
    end
  end

  defp field(row, key, valid?) do
    value = row[key]
    if valid?.(value), do: {:ok, value}, else: {:error, key}
  end

  defp movement_amount(row, key) do
    with {:ok, amount} <- parse_decimal(row[key]),
         false <- Decimal.nan?(amount) or Decimal.inf?(amount) do
      {:ok, amount}
    else
      _ -> {:error, key}
    end
  end

  defp movement_date(date) do
    case Date.from_iso8601(String.slice(date, 0, 10)) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, "datVyst"}
    end
  end

  def list(page \\ 1) do
    cfg = Accommodation.config()

    Repo.all(
      from m in BankMovement,
        where: ^target(cfg),
        order_by: [desc: m.paid_on, desc: m.remote_id],
        limit: 50,
        offset: ^((page - 1) * 50)
    )
    |> Enum.map(&suggestion(&1, cfg))
  end

  def for_booking(booking_id) do
    cfg = Accommodation.config()

    symbols =
      Repo.all(from d in Document, where: d.booking_id == ^booking_id, select: d.variable_symbol)

    Repo.all(
      from m in BankMovement,
        where: ^target(cfg),
        where: m.variable_symbol in ^symbols,
        order_by: [desc: m.paid_on]
    )
    |> Enum.map(&suggestion(&1, cfg))
    |> Enum.filter(&(&1.booking_id == booking_id))
  end

  defp suggestion(movement, cfg) do
    base = %{movement: movement, booking_id: nil, document: nil, difference: nil}

    cond do
      movement.missing_at ->
        Map.put(base, :reason, "Pohyb v posledním načtení chybí")

      movement.currency != "code:CZK" ->
        Map.put(base, :reason, "Cizí měna")

      movement.direction != "typPohybu.prijem" ->
        Map.put(base, :reason, "Odchozí pohyb – ruční kontrola vratky")

      not Decimal.positive?(movement.amount) ->
        Map.put(base, :reason, "Neplatná částka příjmu")

      movement.pairing == "paired" ->
        Map.put(base, :reason, "ABRA hlásí párování – ruční kontrola")

      movement.variable_symbol in [nil, ""] ->
        Map.put(base, :reason, "Chybí VS")

      not match?(%DateTime{}, cfg[:enabled_from]) ->
        Map.put(base, :reason, "Chybí okamžik zapojení nových pobytů")

      true ->
        match_documents(base, cfg)
    end
  end

  defp match_documents(base, cfg) do
    docs =
      Repo.all(
        from d in Document,
          join: b in Booking,
          on: b.id == d.booking_id,
          where: d.variable_symbol == ^base.movement.variable_symbol,
          where: d.kind in ["advance", "final"] and b.inserted_at >= ^cfg[:enabled_from],
          where: is_nil(b.deleted_at)
      )

    case Enum.group_by(docs, & &1.booking_id) |> Map.to_list() do
      [{booking_id, matches}] ->
        # A late balance payment with the old advance VS belongs to the final invoice.
        target =
          Repo.one(from d in Document, where: d.booking_id == ^booking_id and d.kind == "final")

        target = target || if(length(matches) == 1, do: hd(matches))

        if target do
          received = Billing.list_payments(booking_id)

          reason =
            if received == [],
              do: "Návrh podle VS – dostupnost platby není ověřena",
              else: "Návrh podle VS – pobyt již má evidované platby, ověřte duplicitu"

          expected =
            if target.kind == "final",
              do: Billing.balance(booking_id).outstanding,
              else: target.total

          Map.merge(base, %{
            booking_id: booking_id,
            document: target,
            difference: Decimal.sub(base.movement.amount, expected),
            reason: reason
          })
        else
          Map.put(base, :reason, "Nejednoznačný cílový doklad")
        end

      [] ->
        Map.put(base, :reason, "VS neodpovídá dokladu nového pobytu")

      _ ->
        Map.put(base, :reason, "VS odpovídá více pobytům")
    end
  end

  defp configured? do
    cfg = Accommodation.config()

    enabled?() and
      Enum.all?(
        [:base_url, :company_id, :username, :password, :bank_account_code],
        &(is_binary(cfg[&1]) and String.trim(cfg[&1]) != "")
      )
  end

  defp target(cfg),
    do: [
      base_url: cfg[:base_url],
      company_id: cfg[:company_id],
      account: "code:#{cfg[:bank_account_code]}"
    ]

  defp parse_decimal(value) when is_binary(value) or is_integer(value) or is_float(value) do
    case Decimal.parse(to_string(value)) do
      {amount, ""} -> {:ok, amount}
      _ -> :error
    end
  end

  defp parse_decimal(_), do: :error
end
