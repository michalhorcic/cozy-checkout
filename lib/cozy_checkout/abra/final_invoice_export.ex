defmodule CozyCheckout.Abra.FinalInvoiceExport do
  @moduledoc "Final accommodation invoice export with source ZDD deductions."
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

  def enabled?(cfg \\ Accommodation.config()), do: cfg[:enabled] == true

  def prepare(%Document{kind: "final"} = doc, cfg) do
    required =
      ~w(final_type_code final_vat_code final_vat_report_code final_service_account final_fee_account final_outside_vat_code final_outside_vat_report_code)a

    cond do
      not enabled?(cfg) ->
        {:error, "Export vyúčtování není zapnutý"}

      Enum.any?(required, &(cfg[&1] in [nil, ""])) ->
        {:error, "Chybí mapování vyúčtování"}

      cfg[:final_type_code] in [cfg[:advance_type_code], cfg[:tax_receipt_type_code]] ->
        {:error, "Vyúčtování potřebuje vlastní typ faktury, nikoli typ zálohy nebo ZDD"}

      Repo.exists?(
        from p in Payment, where: p.booking_id == ^doc.booking_id and p.kind == "refund"
      ) ->
        {:error, "Pobyt s vratkou vyžaduje účetní vzor; export je pozastaven"}

      Repo.exists?(
        from d in Document, where: d.booking_id == ^doc.booking_id and d.kind == "correction"
      ) ->
        {:error, "Pobyt s opravou vyžaduje účetní vzor; export je pozastaven"}

      Repo.exists?(from p in Payment, where: p.document_id == ^doc.id) ->
        {:error, "Faktura již má místní doplatek; jeho účetní přenos zatím není podporovaný"}

      true ->
        with {:ok, sources} <- sources(doc, cfg),
             {:ok, payload, expected} <- FinalInvoiceBuilder.build(doc, sources, cfg) do
          {:ok, payload, %{"kind" => "final", "sources" => sources, "expected" => expected}}
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

        not is_nil(confirmation) and confirmation.state in ["queued", "retrying"] and
            CozyCheckout.Abra.BankPayments.same_target?(confirmation, cfg) ->
          {:halt, {:waiting, "Čeká na dokončení přenosu zdrojového ZDD a jeho bankovních vazeb"}}

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
         :ok <- verify_sources(export.verification["sources"], cfg),
         :ok <- ensure_invoice(export, invoice, cfg) do
      complete_deductions(export, invoice, cfg, [])
    end
  end

  defp ensure_invoice(export, invoice, cfg) do
    case Client.read_invoice(export.external_id, cfg) do
      {:ok, _} ->
        :ok

      :not_found ->
        # Deduction is an operation on an already persisted invoice. Keep the
        # immutable payload, but send its create and deduction operations separately.
        payload =
          put_in(export.payload, ["winstrom", "faktura-vydana"], [
            Map.delete(invoice, "odpocty-zaloh")
          ])

        with :ok <- available_sources(export.verification["sources"], cfg),
             {:ok, _} <- Client.create_invoice(payload, cfg),
             do: :ok

      error ->
        error
    end
  end

  defp complete_deductions(export, invoice, cfg, required_ids) do
    source_ids = Enum.map(export.verification["sources"], & &1["remote_id"])

    with {:ok, snapshot} <- Client.final_invoice_snapshot(export.external_id, cfg, source_ids),
         {:ok, applied} <-
           CozyCheckout.Abra.FinalInvoiceVerification.progress(
             invoice,
             export.verification,
             snapshot
           ) do
      applied_ids = Enum.map(applied, & &1["document_id"])
      pending = Enum.find(export.verification["sources"], &(&1["document_id"] not in applied_ids))

      cond do
        not Enum.all?(required_ids, &(&1 in applied_ids)) ->
          {:error, "ABRA nepotvrdila odpočet ZDD; přenos je pozastaven do další kontroly"}

        is_nil(pending) ->
          {:ok, to_string(snapshot.invoice["id"])}

        true ->
          # Older frozen exports used the XML-shaped wrapper. Read it without
          # rewriting the snapshot; Client always sends the JSON array form.
          operations =
            case invoice["odpocty-zaloh"] do
              %{"odpocet" => operations} when is_list(operations) -> operations
              operations when is_list(operations) -> operations
              _ -> []
            end

          deduction =
            Enum.find(
              operations,
              &(&1["id"] == pending["deduction_id"] and &1["doklad"] == pending["remote_id"])
            )

          if deduction do
            with :ok <- available_sources([pending], cfg),
                 :ok <-
                   Client.apply_invoice_deduction(
                     to_string(snapshot.invoice["id"]),
                     deduction,
                     cfg
                   ) do
              complete_deductions(export, invoice, cfg, [pending["document_id"] | applied_ids])
            end
          else
            {:error, "Uložený odpočet neodpovídá zdrojovému ZDD; nic se nepřepisuje"}
          end
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
end
