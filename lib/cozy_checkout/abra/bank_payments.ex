defmodule CozyCheckout.Abra.BankPayments do
  @moduledoc "Explicit confirmation of bank advances, atomic local receipt/ZDD/outbox, and retryable remote links."
  import Ecto.Query
  alias CozyCheckout.{Billing, Repo}

  alias CozyCheckout.Abra.{
    Accommodation,
    BankConfirmation,
    BankMovement,
    BankVerification,
    Client,
    TaxReceiptBuilder
  }

  alias CozyCheckout.Billing.Payment
  alias CozyCheckout.Bookings.Booking
  alias CozyCheckout.Workers.AbraBankPaymentWorker

  @salt "abra-bank-confirmation"
  def enabled_for?("final"), do: CozyCheckout.Abra.FinalBankPayments.enabled?()
  def enabled_for?(_), do: enabled?()
  def enabled?, do: Accommodation.config()[:bank_confirmation_enabled] == true
  def state_label("queued"), do: "Čeká na přenos"
  def state_label("retrying"), do: "Opakuje se přenos"
  def state_label("failed"), do: "Chyba přenosu"
  def state_label("conflict"), do: "Vyžaduje účetní kontrolu"
  def state_label("synced"), do: "Přeneseno"
  def get(movement_id), do: Repo.get_by(BankConfirmation, movement_id: movement_id)

  def preview(movement_id, document_id) do
    with {:ok, prepared} <- prepare(movement_id, document_id) do
      data = %{movement_id: movement_id, document_id: document_id, digest: digest(prepared)}
      {:ok, Map.put(prepared, :token, Phoenix.Token.sign(CozyCheckoutWeb.Endpoint, @salt, data))}
    end
  end

  def confirm(token) do
    with {:ok, data} <- Phoenix.Token.verify(CozyCheckoutWeb.Endpoint, @salt, token, max_age: 300) do
      case get(data.movement_id) do
        %BankConfirmation{} = confirmation ->
          existing(confirmation, data.document_id)

        nil ->
          with {:ok, prepared} <- prepare(data.movement_id, data.document_id),
               true <- digest(prepared) == data.digest do
            record(prepared, data.digest)
          else
            false -> {:error, "Návrh se změnil; zkontrolujte jej znovu"}
            error -> error
          end
      end
    else
      _ -> {:error, "Potvrzení vypršelo; načtěte nový náhled"}
    end
  end

  @doc "A remote edit is a conflict, never a rewrite of the recorded payment or ZDD."
  def notice_import(movement) do
    case get(movement.id) do
      %BankConfirmation{} = confirmation ->
        if movement.missing_at ||
             BankVerification.fingerprint(movement.raw) !=
               BankVerification.fingerprint(confirmation.bank_snapshot) do
          confirmation
          |> Ecto.Changeset.change(
            state: "conflict",
            error: "Potvrzený pohyb byl v ABRA změněn nebo chybí; účetní kontrola je nutná"
          )
          |> Repo.update!()
        end

      nil ->
        :ok
    end
  end

  def retry(id) do
    # Recheck uses fresh HTTP reads outside the local transaction. It never
    # edits a remote document or creates a new local payment/ZDD.
    with :ok <- retry_check(id) do
      Repo.transaction(fn ->
        confirmation =
          Repo.one!(from(c in BankConfirmation, where: c.id == ^id, lock: "FOR UPDATE"))

        if not same_target?(confirmation, Accommodation.config()),
          do: Repo.rollback("Cílová firma se změnila")

        if confirmation.state != "synced" do
          {:ok, _} = %{confirmation_id: id} |> AbraBankPaymentWorker.new() |> Oban.insert()
          confirmation |> Ecto.Changeset.change(state: "queued", error: nil) |> Repo.update!()
        else
          confirmation
        end
      end)
    end
  end

  defp retry_check(id) do
    case CozyCheckout.Abra.BankPaymentSync.recheck(id) do
      {:ok, _} -> :ok
      {:conflict, reason} -> {:error, reason}
      result -> result
    end
  end

  defp prepare(movement_id, document_id) do
    case Billing.get_document!(document_id).kind do
      "final" -> CozyCheckout.Abra.FinalBankPayments.prepare(movement_id, document_id)
      _ -> prepare_advance(movement_id, document_id)
    end
  end

  defp prepare_advance(movement_id, document_id) do
    cfg = Accommodation.config()
    movement = Repo.get!(BankMovement, movement_id)
    doc = Billing.get_document!(document_id)
    export = Accommodation.get_export(doc.id)
    booking = Repo.get!(Booking, doc.booking_id)

    cond do
      not enabled?() or not Accommodation.enabled?() or not TaxReceiptBuilder.configured?(cfg) ->
        {:error, "Potvrzování plateb je vypnuté nebo chybí konfigurace ZDD"}

      not same_target?(movement, cfg) or movement.account != "code:#{cfg[:bank_account_code]}" ->
        {:error, "Pohyb patří jinému účtu nebo cílové firmě"}

      not match?(%DateTime{}, cfg[:enabled_from]) or
        DateTime.compare(booking.inserted_at, cfg[:enabled_from]) == :lt or booking.deleted_at ->
        {:error, "Pobyt není zapojen do nové integrace"}

      doc.kind != "advance" or movement.variable_symbol != doc.variable_symbol ->
        {:error, "Tento blok potvrzuje pouze zálohu se shodným VS výzvy"}

      is_nil(export) or export.state != "synced" or not same_target?(export, cfg) ->
        {:error, "Nejprve úspěšně exportujte zálohovou výzvu do stejné firmy"}

      true ->
        with {:ok, snapshot} <- Client.bank_snapshot(movement.remote_id, cfg),
             {:ok, remote} <- Client.read_invoice(export.external_id, cfg),
             {:ok, links} <- BankVerification.check(snapshot, movement.raw, export.remote_id),
             :ok <- verify_source(export, remote, movement.amount, links.source_paired?),
             {:ok, tax_preview} <-
               Billing.preview_advance_payment(doc.booking_id, movement.amount, movement.paid_on),
             true <- TaxReceiptBuilder.supported_lines?(tax_preview.lines, cfg) do
          {:ok,
           %{
             movement: movement,
             document: doc,
             export: export,
             bank_snapshot: snapshot.bank,
             tax_preview: tax_preview,
             config: cfg
           }}
        else
          false -> {:error, "ZDD obsahuje sazbu nebo daňový režim bez ověřeného mapování"}
          :not_found -> {:error, "Zdrojová výzva v ABRA chybí"}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp record(prepared, expected_digest) do
    Repo.transaction(fn ->
      doc = prepared.document
      booking = Repo.one!(from(b in Booking, where: b.id == ^doc.booking_id, lock: "FOR UPDATE"))

      if doc.kind == "final" and not is_nil(booking.deleted_at),
        do: Repo.rollback("Pobyt byl mezitím odstraněn")

      if doc.kind == "final" and Accommodation.get_export(doc.id) != prepared.export,
        do: Repo.rollback("Stav exportu konečné faktury se mezitím změnil")

      movement =
        Repo.one!(
          from(m in BankMovement, where: m.id == ^prepared.movement.id, lock: "FOR UPDATE")
        )

      case get(movement.id) do
        %BankConfirmation{} = confirmation ->
          case existing(confirmation, doc.id) do
            {:ok, existing} -> existing
            {:error, reason} -> Repo.rollback(reason)
          end

        nil ->
          if BankVerification.fingerprint(movement.raw) !=
               BankVerification.fingerprint(prepared.bank_snapshot),
             do: Repo.rollback("Pohyb byl mezitím změněn importem")

          current_preview =
            case local_preview(doc, movement) do
              {:ok, preview} -> preview
              {:error, reason} -> Repo.rollback(reason)
            end

          current = %{prepared | tax_preview: current_preview, config: Accommodation.config()}

          if digest(current) != expected_digest or not enabled_for?(doc.kind),
            do: Repo.rollback("Návrh nebo konfigurace se mezitím změnily")

          recorded =
            Repo.one(
              from(p in Payment,
                where: p.document_id == ^doc.id and p.kind == "receipt",
                select: coalesce(sum(p.amount), 0)
              )
            )

          limit =
            if doc.kind == "final",
              do: CozyCheckout.Abra.FinalBankPayments.payable(doc),
              else: doc.total

          if Decimal.gt?(movement.amount, Decimal.sub(limit, recorded)),
            do: Repo.rollback("Na dokladu již místně zbývá méně; přeplatek vyřešte ručně")

          duplicate =
            Repo.exists?(
              from(p in Payment,
                left_join: c in BankConfirmation,
                on: c.payment_id == p.id,
                where:
                  p.booking_id == ^doc.booking_id and p.method == "bank" and p.kind == "receipt",
                where:
                  p.amount == ^movement.amount and p.paid_on == ^movement.paid_on and is_nil(c.id)
              )
            )

          if duplicate,
            do:
              Repo.rollback("Stejná bankovní platba již může být zapsána ručně; ověřte duplicitu")

          if Repo.exists?(from(p in Payment, where: p.request_id == ^movement.id)),
            do: Repo.rollback("Identita pohybu již byla použita")

          attrs = %{
            "request_id" => movement.id,
            "kind" => "receipt",
            "amount" => to_string(movement.amount),
            "paid_on" => to_string(movement.paid_on),
            "method" => "bank",
            "document_id" => doc.id,
            "reference" => "ABRA banka #{movement.company_id}/#{movement.remote_id}"
          }

          payment =
            case Billing.record_payment(doc.booking_id, attrs) do
              {:ok, payment} -> payment
              {:error, reason} -> Repo.rollback(reason)
            end

          payload = receipt_payload(payment, current.config, doc.kind)

          confirmation =
            %BankConfirmation{}
            |> Ecto.Changeset.change(
              kind: doc.kind,
              movement_id: movement.id,
              payment_id: payment.id,
              source_export_id: prepared.export.id,
              base_url: movement.base_url,
              company_id: movement.company_id,
              bank_snapshot: prepared.bank_snapshot,
              receipt_payload: payload
            )
            |> Repo.insert!()

          {:ok, _} =
            %{confirmation_id: confirmation.id} |> AbraBankPaymentWorker.new() |> Oban.insert()

          confirmation
      end
    end)
  end

  defp local_preview(%{kind: "final"} = doc, movement),
    do: CozyCheckout.Abra.FinalBankPayments.local_preview(doc, movement)

  defp local_preview(doc, movement),
    do: Billing.preview_advance_payment(doc.booking_id, movement.amount, movement.paid_on)

  defp receipt_payload(_payment, _cfg, "final"), do: %{}

  defp receipt_payload(payment, cfg, _) do
    case TaxReceiptBuilder.build(Billing.get_document!(payment.tax_document_id), cfg) do
      {:ok, payload} -> payload
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp existing(confirmation, document_id) do
    payment = Repo.get!(Payment, confirmation.payment_id)

    if payment.document_id == document_id,
      do: {:ok, confirmation},
      else: {:error, "Pohyb již patří jinému dokladu"}
  end

  defp digest(prepared) do
    {prepared.document.id, prepared.export.id,
     BankVerification.fingerprint(prepared.bank_snapshot), prepared.tax_preview.token,
     Map.get(prepared, :remote_digest), Keyword.drop(prepared.config, [:username, :password])}
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16()
  end

  def verify_source(export, remote, amount, paired?) do
    [invoice] = export.payload["winstrom"]["faktura-vydana"]

    expected =
      invoice["polozkyFaktury"] |> Enum.map(&Decimal.new(&1["cenaMj"])) |> Billing.Money.sum()

    remaining = BankVerification.amount(remote["zbyvaUhradit"])

    valid? =
      to_string(remote["id"]) == export.remote_id and remote["kod"] == invoice["kod"] and
        remote["varSym"] == invoice["varSym"] and remote["mena"] == "code:CZK" and
        remote["typDokl"] == invoice["typDokl"] and remote["ucetni"] in [false, "false"] and
        remote["bankovniUcet"] == invoice["bankovniUcet"] and
        remote["clenDph"] == invoice["clenDph"] and
        remote["clenKonVykDph"] == invoice["clenKonVykDph"] and
        remote["storno"] in [false, "false"] and
        BankVerification.equal?(remote["sumCelkem"], expected)

    cond do
      not valid? ->
        {:error, "Zdrojová výzva v ABRA neodpovídá uloženému exportu"}

      not paired? and (is_nil(remaining) or Decimal.lt?(remaining, amount)) ->
        {:error, "Výzva nemá dostatečnou zbývající částku; přeplatek nebo úhradu vyřešte ručně"}

      true ->
        :ok
    end
  end

  def same_target?(record, cfg),
    do: record.base_url == cfg[:base_url] and record.company_id == cfg[:company_id]
end
