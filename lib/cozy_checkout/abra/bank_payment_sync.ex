defmodule CozyCheckout.Abra.BankPaymentSync do
  @moduledoc "Recovery by stable invoice identity and read-back of existing bank relationships."
  import Ecto.Query
  alias CozyCheckout.Repo

  alias CozyCheckout.Abra.{
    Accommodation,
    AccommodationExport,
    BankConfirmation,
    BankPayments,
    BankVerification,
    Client,
    TaxReceiptVerification
  }

  def sync(id, final? \\ false) do
    confirmation = Repo.get!(BankConfirmation, id) |> Repo.preload(:movement)
    cfg = Accommodation.config()

    cond do
      confirmation.state in ["synced", "conflict"] ->
        :ok

      not BankPayments.enabled?() or not Accommodation.enabled?() ->
        {:snooze, 60}

      not BankPayments.same_target?(confirmation, cfg) ->
        fail(confirmation, "Cílová firma se změnila", :conflict)

      true ->
        confirmation =
          confirmation
          |> Ecto.Changeset.change(attempts: confirmation.attempts + 1)
          |> Repo.update!()

        case deliver(confirmation, cfg) do
          {:ok, receipt_id} ->
            Repo.transaction(fn ->
              current =
                Repo.one!(
                  from c in BankConfirmation, where: c.id == ^confirmation.id, lock: "FOR UPDATE"
                )

              if current.state != "conflict" do
                current
                |> Ecto.Changeset.change(
                  state: "synced",
                  remote_receipt_id: receipt_id,
                  error: nil,
                  synced_at: DateTime.utc_now(:second)
                )
                |> Repo.update!()
              end
            end)

            :ok

          {:conflict, reason} ->
            fail(confirmation, reason, :conflict)

          {:error, reason} ->
            fail(confirmation, reason, if(final?, do: :failed, else: :retrying))
        end
    end
  end

  @doc "Read-only preflight before manually resuming an existing confirmation."
  def recheck(id) do
    confirmation = Repo.get!(BankConfirmation, id) |> Repo.preload(:movement)
    cfg = Accommodation.config()
    source = Repo.get!(AccommodationExport, confirmation.source_export_id)
    [invoice] = confirmation.receipt_payload["winstrom"]["faktura-vydana"]

    cond do
      confirmation.state == "synced" ->
        :ok

      not BankPayments.enabled?() or not Accommodation.enabled?() ->
        {:error, "Účetní synchronizace je vypnutá"}

      not BankPayments.same_target?(confirmation, cfg) ->
        {:error, "Cílová firma se změnila"}

      true ->
        with :ok <- source_ready(source, cfg),
             {:ok, remote_source} <- read_source(source, cfg),
             {:ok, remote_receipt} <- lookup_receipt(invoice, cfg),
             {:ok, links} <- checked_bank(confirmation, source, remote_receipt, cfg),
             :ok <-
               BankPayments.verify_source(
                 source,
                 remote_source,
                 confirmation.movement.amount,
                 links.source_paired?
               ) do
          :ok
        else
          {:conflict, reason} -> {:error, reason}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp deliver(confirmation, cfg) do
    source = Repo.get!(AccommodationExport, confirmation.source_export_id)
    [invoice] = confirmation.receipt_payload["winstrom"]["faktura-vydana"]

    with :ok <- source_ready(source, cfg),
         {:ok, remote_source} <- read_source(source, cfg),
         {:ok, remote_receipt} <- lookup_receipt(invoice, cfg),
         {:ok, before} <- checked_bank(confirmation, source, remote_receipt, cfg),
         :ok <-
           conflict(
             BankPayments.verify_source(
               source,
               remote_source,
               confirmation.movement.amount,
               before.source_paired?
             )
           ),
         {:ok, receipt_id} <- ensure_receipt(confirmation, invoice, remote_receipt, cfg),
         :ok <- ensure_match(confirmation, source, before, cfg),
         {:ok, paired} <- checked_bank(confirmation, source, %{"id" => receipt_id}, cfg),
         :ok <- require_pair(paired),
         :ok <- ensure_zdd_link(confirmation, receipt_id, paired, cfg),
         {:ok, linked} <- checked_bank(confirmation, source, %{"id" => receipt_id}, cfg),
         :ok <- require_complete(linked) do
      {:ok, receipt_id}
    end
  end

  defp source_ready(source, cfg) do
    cond do
      not BankPayments.same_target?(source, cfg) -> {:conflict, "Výzva patří jiné cílové firmě"}
      source.state != "synced" -> {:error, "Čeká se na export zálohové výzvy"}
      true -> :ok
    end
  end

  defp read_source(source, cfg) do
    case Client.read_invoice(source.external_id, cfg) do
      :not_found -> {:conflict, "Zdrojová výzva byla v ABRA odstraněna"}
      result -> result
    end
  end

  defp lookup_receipt(invoice, cfg) do
    case Client.read_invoice(invoice["id"], cfg) do
      :not_found ->
        {:ok, nil}

      {:ok, remote} ->
        with :ok <- conflict(TaxReceiptVerification.check(invoice, remote)), do: {:ok, remote}

      error ->
        error
    end
  end

  defp checked_bank(confirmation, source, receipt, cfg) do
    with {:ok, snapshot} <- Client.bank_snapshot(confirmation.movement.remote_id, cfg) do
      conflict(
        BankVerification.check(
          snapshot,
          confirmation.bank_snapshot,
          source.remote_id,
          if(receipt, do: to_string(receipt["id"]))
        )
      )
    else
      {:error, :not_found} -> {:conflict, "Potvrzený bankovní pohyb v ABRA chybí"}
      error -> error
    end
  end

  defp ensure_receipt(_confirmation, _invoice, %{"id" => id}, _cfg), do: {:ok, to_string(id)}

  defp ensure_receipt(confirmation, invoice, nil, cfg) do
    with {:ok, _} <- Client.create_invoice(confirmation.receipt_payload, cfg),
         {:ok, remote} <- lookup_receipt(invoice, cfg) do
      if remote,
        do: {:ok, to_string(remote["id"])},
        else: {:error, "ZDD po importu chybí pod externím ID"}
    end
  end

  defp ensure_match(_confirmation, _source, %{source_paired?: true}, _cfg), do: :ok

  defp ensure_match(confirmation, source, _before, cfg) do
    Client.match_bank(
      confirmation.movement.remote_id,
      source.remote_id,
      confirmation.movement.amount,
      cfg
    )
  end

  defp ensure_zdd_link(_confirmation, _receipt_id, %{receipt_linked?: true}, _cfg), do: :ok

  defp ensure_zdd_link(confirmation, receipt_id, _paired, cfg),
    do: Client.link_tax_receipt(receipt_id, confirmation.movement.remote_id, cfg)

  defp require_pair(%{source_paired?: true}), do: :ok
  defp require_pair(_), do: {:error, "ABRA nepotvrdila vazbu úhrady výzvy"}
  defp require_complete(%{source_paired?: true, receipt_linked?: true}), do: :ok
  defp require_complete(_), do: {:error, "ABRA nepotvrdila obě účetní vazby"}

  defp conflict({:error, reason}), do: {:conflict, reason}
  defp conflict(result), do: result

  defp fail(confirmation, reason, state) do
    Repo.update_all(
      from(c in BankConfirmation, where: c.id == ^confirmation.id and c.state != "conflict"),
      set: [
        state: to_string(state),
        error: to_string(reason),
        updated_at: DateTime.utc_now(:second)
      ]
    )

    if state in [:failed, :conflict], do: {:cancel, reason}, else: {:error, reason}
  end
end
