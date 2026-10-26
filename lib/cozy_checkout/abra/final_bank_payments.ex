defmodule CozyCheckout.Abra.FinalBankPayments do
  @moduledoc "Existing-bank settlement of an exported final invoice, without ZDD or document writes."
  import Ecto.Query
  alias CozyCheckout.{Billing, Repo}
  alias CozyCheckout.Billing.{Document, Money, Payment}
  alias CozyCheckout.Bookings.Booking

  alias CozyCheckout.Abra.{
    Accommodation,
    AccommodationExport,
    BankConfirmation,
    BankMovement,
    BankPayments,
    BankVerification,
    Client,
    FinalInvoiceVerification
  }

  def enabled?, do: Accommodation.config()[:final_bank_confirmation_enabled] == true
  def payable(doc), do: Decimal.add(doc.total, Money.total(doc.snapshot["deductions"] || []))

  def local_preview(doc, movement) do
    payments = Billing.list_payments(doc.booking_id) |> Enum.sort_by(& &1.id)

    received =
      payments |> Enum.filter(&(&1.document_id == doc.id)) |> Enum.map(& &1.amount) |> Money.sum()

    cond do
      Repo.exists?(
        from(d in Document, where: d.booking_id == ^doc.booking_id and d.kind == "correction")
      ) or
          Enum.any?(payments, &(&1.kind == "refund")) ->
        {:error, "Doplatek pobytu s opravou nebo vratkou vyžaduje ruční účetní řešení"}

      Date.compare(movement.paid_on, doc.tax_date) == :lt ->
        {:error, "Platba před DUZP je záloha; nelze ji potvrdit jako doplatek"}

      Decimal.gt?(movement.amount, Decimal.sub(payable(doc), received)) ->
        {:error, "Přeplatek: na konečné faktuře místně zbývá méně než celý pohyb"}

      true ->
        {:ok, %{token: :erlang.term_to_binary({doc, payments}) |> Base.encode64()}}
    end
  end

  def prepare(movement_id, document_id) do
    cfg = Accommodation.config()
    movement = Repo.get!(BankMovement, movement_id)
    doc = Billing.get_document!(document_id)
    export = Accommodation.get_export(doc.id)
    booking = Repo.get!(Booking, doc.booking_id)

    cond do
      not enabled?() or not Accommodation.enabled?() ->
        {:error, "Potvrzování bankovních doplatků je vypnuté"}

      not BankPayments.same_target?(movement, cfg) or
        movement.account != "code:#{cfg[:bank_account_code]}" or movement.missing_at ->
        {:error, "Pohyb chybí nebo patří jinému účtu či firmě"}

      not match?(%DateTime{}, cfg[:enabled_from]) or not is_nil(booking.deleted_at) or
          DateTime.compare(booking.inserted_at, cfg[:enabled_from]) == :lt ->
        {:error, "Pobyt není zapojen do nové integrace"}

      doc.kind != "final" or movement.variable_symbol != doc.variable_symbol ->
        {:error, "Doplatek vyžaduje VS konečné faktury; původní záloha se znovu nepáruje"}

      is_nil(export) or export.state != "synced" or not BankPayments.same_target?(export, cfg) or
          export.verification["kind"] != "final" ->
        {:error, "Nejprve dokončete export konečné faktury s odpočty do stejné firmy"}

      true ->
        with {:ok, preview} <- local_preview(doc, movement),
             {:ok, checked} <- checked(export, movement, movement.raw, cfg) do
          {:ok,
           %{
             movement: movement,
             document: doc,
             export: export,
             bank_snapshot: checked.bank,
             tax_preview: preview,
             config: cfg,
             remote_digest: checked.digest
           }}
        else
          {:conflict, reason} -> {:error, reason}
          error -> error
        end
    end
  end

  defp semantic({:error, reason}), do: {:conflict, reason}
  defp semantic(result), do: result

  defp direct_bank(bank, snapshot) do
    {direct, indirect} = Enum.split_with(bank.links, &(to_string(&1["uroven"]) in ["0", "1"]))

    if Enum.all?(indirect, fn row ->
         Enum.any?(snapshot.links, fn target ->
           Enum.all?(~w(idVazby idDokl modulK typVazbyK storno), &(row[&1] == target[&1])) and
             to_string(row["uroven"]) == to_string(parse_level(target["uroven"]) + 1)
         end)
       end),
       do: {:ok, %{bank | links: direct}},
       else: {:conflict, "Graf bankovního pohybu obsahuje neověřenou nepřímou vazbu"}
  end

  defp parse_level(value) do
    case Integer.parse(to_string(value)) do
      {level, ""} -> level
      _ -> -100
    end
  end

  # All HTTP is outside local transactions. Read bank links first, then invoice
  # totals; an inconsistent concurrent remote edit blocks writes or completion.
  defp checked(export, movement, expected_bank, cfg) do
    with {:ok, bank} <- Client.bank_snapshot(movement.remote_id, cfg),
         {:ok, snapshot} <-
           Client.final_invoice_snapshot(
             export.external_id,
             cfg,
             Enum.map(export.verification["sources"], & &1["remote_id"])
           ),
         {:ok, direct_bank} <- direct_bank(bank, snapshot),
         {:ok, links} <-
           semantic(BankVerification.check(direct_bank, expected_bank, export.remote_id)),
         :ok <- semantic(only_invoice_payment(bank)),
         {:ok, paid, paired_ids} <- semantic(invoice_payments(snapshot, export, movement, cfg)),
         true <- links.source_paired? == MapSet.member?(paired_ids, movement.remote_id),
         true <- matching_binding_ids?(bank, snapshot, movement),
         :ok <- semantic(verify_invoice(export, snapshot, paid)),
         :ok <- semantic(available(snapshot.invoice, movement.amount, links.source_paired?)) do
      {:ok,
       %{
         bank: bank.bank,
         paired?: links.source_paired?,
         digest:
           :erlang.term_to_binary(
             {snapshot.invoice, snapshot.amounts, snapshot.items, snapshot.links,
              snapshot.source_bindings}
           )
           |> Base.encode64()
       }}
    else
      false -> {:conflict, "Vazby banky a konečné faktury si odporují; obnovte kontrolu"}
      error -> error
    end
  end

  defp matching_binding_ids?(bank, snapshot, movement) do
    bank_ids =
      bank.amounts
      |> Enum.filter(&(&1["storno"] in [false, "false"]))
      |> MapSet.new(&to_string(&1["id"]))

    invoice_ids =
      snapshot.amounts
      |> Enum.filter(fn binding ->
        binding["storno"] in [false, "false"] and binding["typVazbyK"] == "typVazbyDokl.uhrada" and
          reference(binding["b@ref"]) == {movement.company_id, "banka", movement.remote_id}
      end)
      |> MapSet.new(&to_string(&1["id"]))

    bank_ids == invoice_ids
  end

  defp only_invoice_payment(snapshot) do
    if Enum.all?(
         snapshot.amounts,
         &(&1["storno"] in [true, "true"] or &1["typVazbyK"] == "typVazbyDokl.uhrada")
       ),
       do: :ok,
       else:
         {:error, "Pohyb má zálohovou, ZDD nebo jinou vazbu; rozdělení pohybu není podporováno"}
  end

  defp invoice_payments(snapshot, export, movement, cfg) do
    known =
      Repo.all(
        from(c in BankConfirmation,
          join: p in Payment,
          on: p.id == c.payment_id,
          join: m in BankMovement,
          on: m.id == c.movement_id,
          where: c.kind == "final" and c.source_export_id == ^export.id,
          select: {m.remote_id, p.amount}
        )
      )
      |> Map.new()
      |> Map.put(movement.remote_id, movement.amount)

    bindings = Enum.filter(snapshot.amounts, &(&1["typVazbyK"] == "typVazbyDokl.uhrada"))

    payment_links =
      Enum.filter(
        snapshot.links,
        &(&1["typVazbyK"] == "typVazbyDokl.uhrada" and to_string(&1["uroven"]) == "1")
      )

    active_links = Enum.filter(payment_links, &(&1["storno"] in [false, "false"]))
    active_bindings = Enum.filter(bindings, &(&1["storno"] in [false, "false"]))

    complete? =
      Enum.all?(payment_links ++ bindings, &(&1["storno"] in [true, false, "true", "false"])) and
        length(Enum.uniq_by(active_bindings, &to_string(&1["id"]))) == length(active_bindings) and
        length(Enum.uniq_by(active_links, &to_string(&1["idVazby"]))) == length(active_links) and
        MapSet.new(active_links, &to_string(&1["idVazby"])) ==
          MapSet.new(active_bindings, &to_string(&1["id"]))

    result =
      Enum.reduce_while(bindings, {:ok, Decimal.new(0), MapSet.new()}, fn binding,
                                                                          {:ok, sum, ids} ->
        if binding["storno"] in [true, "true"] do
          {:cont, {:ok, sum, ids}}
        else
          with false <- binding["storno"] not in [false, "false"],
               {company, "faktura-vydana", invoice_id} <- reference(binding["a@ref"]),
               {^company, "banka", bank_id} <- reference(binding["b@ref"]),
               true <- company == cfg[:company_id] and invoice_id == export.remote_id,
               true <-
                 binding["a@internalId"] == nil or
                   to_string(binding["a@internalId"]) == invoice_id,
               true <-
                 binding["b@internalId"] == nil or to_string(binding["b@internalId"]) == bank_id,
               %Decimal{} = amount <- known[bank_id],
               true <- BankVerification.equal?(binding["castka"], amount),
               false <- MapSet.member?(ids, bank_id),
               true <-
                 Enum.any?(
                   snapshot.links,
                   &(to_string(&1["idVazby"]) == to_string(binding["id"]) and
                       to_string(&1["idDokl"]) == bank_id and &1["modulK"] == "modulUcetni.BAN" and
                       to_string(&1["uroven"]) == "1" and &1["storno"] in [false, "false"] and
                       &1["typVazbyK"] == "typVazbyDokl.uhrada")
                 ) do
            {:cont, {:ok, Decimal.add(sum, amount), MapSet.put(ids, bank_id)}}
          else
            _ ->
              {:halt, {:error, "Neznámá, konfliktní nebo neúplná přímá úhrada konečné faktury"}}
          end
        end
      end)

    synced =
      Repo.all(
        from(c in BankConfirmation,
          join: m in BankMovement,
          on: m.id == c.movement_id,
          where: c.kind == "final" and c.source_export_id == ^export.id and c.state == "synced",
          select: m.remote_id
        )
      )

    case result do
      {:ok, _, ids} ->
        if complete? and Enum.all?(synced, &MapSet.member?(ids, &1)),
          do: result,
          else: {:error, "Neúplné vazby úhrad nebo dříve přenesená úhrada v ABRA chybí"}

      error ->
        error
    end
  end

  # Official payment bindings: a = invoice, b = bank. Accept /c/ and /v2/c/.
  defp reference(ref) when is_binary(ref) do
    path = URI.parse(ref).path || ""

    case path
         |> String.replace_prefix("/v2/", "/")
         |> URI.decode()
         |> String.split("/", trim: true) do
      ["c", company, evidence, id] ->
        {company, evidence, String.replace(id, ~r/\.(json|xml)$/, "")}

      _ ->
        nil
    end
  end

  defp reference(_), do: nil

  defp verify_invoice(export, snapshot, paid) do
    expected = export.verification["expected"]
    total = Decimal.new(expected["sumCelkem"])

    metadata =
      Map.put(
        export.verification,
        "expected",
        Map.merge(
          expected,
          %{"juhSum" => to_string(paid), "zbyvaUhradit" => to_string(Decimal.sub(total, paid))}
        )
      )

    [invoice] = export.payload["winstrom"]["faktura-vydana"]
    # The export verifier checks frozen prices, taxes and ZDD deductions. Payment
    # edges are checked above and removed only for this deduction-specific check.
    clean = %{
      snapshot
      | amounts: Enum.reject(snapshot.amounts, &(&1["typVazbyK"] == "typVazbyDokl.uhrada")),
        links: Enum.reject(snapshot.links, &(&1["typVazbyK"] == "typVazbyDokl.uhrada"))
    }

    if to_string(snapshot.invoice["id"]) == export.remote_id and not Decimal.gt?(paid, total),
      do: FinalInvoiceVerification.check(invoice, metadata, clean),
      else: {:error, "Identita nebo přímé úhrady konečné faktury neodpovídají exportu"}
  end

  defp available(invoice, amount, paired?) do
    remaining = BankVerification.amount(invoice["zbyvaUhradit"])

    if remaining && not Decimal.negative?(remaining) &&
         (paired? or not Decimal.gt?(amount, remaining)),
       do: :ok,
       else: {:error, "Přeplatek: ABRA nemá dostatečnou zbývající částku k úhradě celého pohybu"}
  end

  def recheck(confirmation, cfg) do
    export = Repo.get!(AccommodationExport, confirmation.source_export_id)
    doc = Billing.get_document!(export.document_id)

    direct_paid =
      Repo.one(
        from p in Payment,
          where: p.document_id == ^doc.id and p.kind == "receipt",
          select: coalesce(sum(p.amount), 0)
      )

    cond do
      not enabled?() or not Accommodation.enabled?() ->
        {:error, "Přenos doplatků je vypnutý"}

      not BankPayments.same_target?(confirmation, cfg) or
          not BankPayments.same_target?(export, cfg) ->
        {:conflict, "Cílová firma se změnila"}

      confirmation.movement.account != "code:#{cfg[:bank_account_code]}" ->
        {:conflict, "Bankovní účet se změnil"}

      Decimal.gt?(direct_paid, payable(doc)) ->
        {:conflict,
         "Místní doplatky překračují částku konečné faktury; přeplatek vyžaduje účetní kontrolu"}

      export.state != "synced" ->
        {:error, "Export konečné faktury není dokončený"}

      Repo.exists?(
        from(d in Document, where: d.booking_id == ^doc.booking_id and d.kind == "correction")
      ) or
          Repo.exists?(
            from(p in Payment, where: p.booking_id == ^doc.booking_id and p.kind == "refund")
          ) ->
        {:conflict, "Opravy a vratky vyžadují ruční účetní řešení"}

      true ->
        checked(export, confirmation.movement, confirmation.bank_snapshot, cfg)
    end
  end

  def sync(confirmation, cfg, final?) do
    cond do
      confirmation.state in ["synced", "conflict"] ->
        :ok

      not enabled?() or not Accommodation.enabled?() ->
        {:snooze, 60}

      true ->
        Repo.update_all(from(c in BankConfirmation, where: c.id == ^confirmation.id),
          inc: [attempts: 1]
        )

        case deliver(confirmation, cfg) do
          :ok ->
            Repo.update_all(
              from(c in BankConfirmation,
                where: c.id == ^confirmation.id and c.state != "conflict"
              ),
              set: [
                state: "synced",
                error: nil,
                synced_at: DateTime.utc_now(:second),
                updated_at: DateTime.utc_now(:second)
              ]
            )

            :ok

          {type, reason} ->
            state =
              if type == :conflict,
                do: "conflict",
                else: if(final?, do: "failed", else: "retrying")

            Repo.update_all(
              from(c in BankConfirmation,
                where: c.id == ^confirmation.id and c.state not in ["synced", "conflict"]
              ),
              set: [state: state, error: to_string(reason), updated_at: DateTime.utc_now(:second)]
            )

            if state in ["conflict", "failed"], do: {:cancel, reason}, else: {:error, reason}
        end
    end
  end

  defp deliver(confirmation, cfg) do
    with {:ok, before} <- recheck(confirmation, cfg),
         :ok <- ensure_match(confirmation, before, cfg),
         {:ok, after_match} <- recheck(confirmation, cfg) do
      if after_match.paired?, do: :ok, else: {:error, "ABRA nepotvrdila úhradu konečné faktury"}
    end
  end

  defp ensure_match(_, %{paired?: true}, _), do: :ok

  defp ensure_match(confirmation, _, cfg) do
    export = Repo.get!(AccommodationExport, confirmation.source_export_id)

    Client.match_bank(
      confirmation.movement.remote_id,
      export.remote_id,
      confirmation.movement.amount,
      cfg
    )
  end
end
