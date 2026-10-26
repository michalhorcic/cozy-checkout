defmodule CozyCheckout.Abra.FinalInvoiceTrial do
  @moduledoc "Opt-in experimental final invoices for an explicitly pinned accounting test company."
  import Ecto.Query
  alias CozyCheckout.Repo

  alias CozyCheckout.Abra.{
    Accommodation,
    BankConfirmation,
    BankVerification,
    Client,
    FinalInvoiceBuilder,
    TaxReceiptBuilder,
    TaxReceiptVerification
  }

  alias CozyCheckout.Billing.{Document, Payment}

  def enabled?(cfg \\ Accommodation.config()) do
    cfg[:final_trial_enabled] == true and cfg[:final_trial_company_id] not in [nil, ""] and
      cfg[:company_id] == cfg[:final_trial_company_id] and
      cfg[:final_trial_base_url] not in [nil, ""] and cfg[:base_url] == cfg[:final_trial_base_url]
  end

  def prepare(%Document{kind: "final"} = doc, cfg) do
    required =
      ~w(final_trial_type_code final_trial_vat_code final_trial_vat_report_code final_trial_service_account final_trial_fee_account final_trial_outside_vat_code final_trial_outside_vat_report_code)a

    cond do
      not enabled?(cfg) ->
        {:error, "Zkušební export vyúčtování není zapnutý pro tuto testovací firmu"}

      Enum.any?(required, &(cfg[&1] in [nil, ""])) ->
        {:error, "Chybí zkušební mapování vyúčtování"}

      cfg[:final_trial_type_code] in [cfg[:advance_type_code], cfg[:tax_receipt_type_code]] ->
        {:error, "Vyúčtování potřebuje vlastní typ faktury, nikoli typ zálohy nebo ZDD"}

      Repo.exists?(
        from p in Payment, where: p.booking_id == ^doc.booking_id and p.kind == "refund"
      ) ->
        {:error, "Pobyt s vratkou vyžaduje účetní vzor; zkušební export je pozastaven"}

      Repo.exists?(
        from d in Document, where: d.booking_id == ^doc.booking_id and d.kind == "correction"
      ) ->
        {:error, "Pobyt s opravou vyžaduje účetní vzor; zkušební export je pozastaven"}

      Repo.exists?(from p in Payment, where: p.document_id == ^doc.id) ->
        {:error,
         "Faktura již má místní doplatek; jeho účetní přenos zatím není součástí zkušebního bloku"}

      true ->
        with {:ok, sources} <- sources(doc, cfg),
             {:ok, payload, expected} <- FinalInvoiceBuilder.build(doc, sources, cfg) do
          {:ok, payload, %{"kind" => "final_trial", "sources" => sources, "expected" => expected}}
        end
    end
  end

  defp sources(doc, cfg) do
    groups = Enum.group_by(doc.snapshot["deductions"] || [], & &1["source_document_id"])

    Enum.reduce_while(groups, {:ok, []}, fn {source_id, deductions}, {:ok, result} ->
      zdd = Repo.get(Document, source_id)

      confirmation =
        Repo.one(
          from c in BankConfirmation,
            join: p in Payment,
            on: p.id == c.payment_id,
            where: p.tax_document_id == ^source_id
        )

      cond do
        is_nil(zdd) or zdd.kind != "tax_receipt" or zdd.booking_id != doc.booking_id ->
          {:halt, {:error, "Odpočet neodkazuje na ZDD stejného pobytu"}}

        is_nil(confirmation) or confirmation.state != "synced" or
            not CozyCheckout.Abra.BankPayments.same_target?(confirmation, cfg) ->
          {:halt,
           {:error,
            "Nejdřív dokončete přenos všech zdrojových ZDD a jejich bankovních vazeb do stejné firmy"}}

        true ->
          with {:ok, totals} <- TaxReceiptBuilder.summary_totals(zdd.lines, cfg),
               {:ok, negative} <- TaxReceiptBuilder.summary_totals(deductions, cfg),
               true <-
                 Enum.all?(totals, fn {key, value} ->
                   BankVerification.equal?(negative[key], Decimal.negate(Decimal.new(value)))
                 end) do
            source = %{
              "document_id" => source_id,
              "confirmation_id" => confirmation.id,
              "remote_id" => confirmation.remote_receipt_id,
              "payload" => confirmation.receipt_payload,
              "totals" => totals,
              "gross" => to_string(zdd.total),
              "deduction_id" => "ext:cozy-checkout:final-deduction:#{doc.id}:#{source_id}"
            }

            {:cont, {:ok, result ++ [source]}}
          else
            _ ->
              {:halt,
               {:error, "Odpočet se liší od původního rozpisu ZDD; účetní kontrola je nutná"}}
          end
      end
    end)
  end

  def deliver(export, cfg) do
    [invoice] = export.payload["winstrom"]["faktura-vydana"]

    with {:ok, _payload, _verification} <- prepare(Repo.get!(Document, export.document_id), cfg),
         :ok <- verify_sources(export.verification["sources"], cfg) do
      case Client.read_invoice(export.external_id, cfg) do
        {:ok, _} ->
          verify_final(export, invoice, cfg)

        :not_found ->
          with :ok <- available_sources(export.verification["sources"], cfg),
               {:ok, _} <- Client.create_invoice(export.payload, cfg) do
            verify_final(export, invoice, cfg)
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp verify_sources(sources, cfg) do
    Enum.reduce_while(sources, :ok, fn source, :ok ->
      confirmation = Repo.get!(BankConfirmation, source["confirmation_id"])
      [invoice] = source["payload"]["winstrom"]["faktura-vydana"]

      result =
        cond do
          confirmation.state != "synced" or
            not CozyCheckout.Abra.BankPayments.same_target?(confirmation, cfg) or
              confirmation.remote_receipt_id != source["remote_id"] ->
            {:error, "Zdrojové ZDD má konflikt nebo jinou cílovou firmu"}

          true ->
            case Client.read_invoice(invoice["id"], cfg) do
              {:ok, remote} ->
                if to_string(remote["id"]) == source["remote_id"],
                  do: TaxReceiptVerification.check(invoice, remote),
                  else: {:error, "Identita zdrojového ZDD v ABRA se změnila"}

              :not_found ->
                {:error, "Zdrojové ZDD v ABRA chybí"}

              error ->
                error
            end
        end

      if result == :ok, do: {:cont, :ok}, else: {:halt, result}
    end)
  end

  defp available_sources(sources, cfg) do
    Enum.reduce_while(sources, :ok, fn source, :ok ->
      case Client.deductible_amounts(source["remote_id"], cfg) do
        {:ok, available} ->
          if Enum.all?(source["totals"], fn {key, value} ->
               BankVerification.equal?(available[key], Decimal.new(value))
             end),
             do: {:cont, :ok},
             else:
               {:halt, {:error, "ZDD již bylo odečteno nebo zbývající daňové částky nesouhlasí"}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp verify_final(export, invoice, cfg) do
    with {:ok, snapshot} <- Client.final_invoice_snapshot(export.external_id, cfg),
         :ok <-
           CozyCheckout.Abra.FinalInvoiceVerification.check(
             invoice,
             export.verification,
             snapshot
           ) do
      {:ok, to_string(snapshot.invoice["id"])}
    end
  end
end
