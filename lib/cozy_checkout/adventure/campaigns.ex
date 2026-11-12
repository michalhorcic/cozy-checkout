defmodule CozyCheckout.Adventure.Campaigns do
  @moduledoc "Campaign lifecycle and game-only reconciliation. Operational reads use Sources.Stays."
  import Ecto.Query
  alias CozyCheckout.{Adventure, Repo}
  alias CozyCheckout.Adventure.{Campaign, Evaluation, Profile, Unlock, XpTransaction}
  alias CozyCheckout.Adventure.Sources.{Bar, Billing, Stays}

  @achievements [
    %{code: "first_stay", title: "První dokončený pobyt po aktivaci", required: 1, xp: 100},
    %{code: "ten_stays", title: "Deset dokončených pobytů po aktivaci", required: 10, xp: 250}
  ]
  def achievements, do: @achievements

  def overview do
    if Adventure.enabled?() do
      campaigns =
        Repo.all(from c in Campaign, order_by: [desc: c.inserted_at, desc: c.id], limit: 50)
        |> Repo.preload([:last_evaluation, :unlocks])

      xp =
        Repo.one(
          from x in XpTransaction,
            where: x.recipient_type == "shared",
            select: coalesce(sum(x.amount), 0)
        )

      ledger =
        Repo.all(
          from x in XpTransaction,
            where: x.recipient_type == "shared",
            order_by: [desc: x.inserted_at, desc: x.id],
            limit: 20
        )

      evaluations =
        Repo.all(
          from e in Evaluation,
            join: c in Campaign,
            on: c.id == e.campaign_id,
            join: p in Profile,
            on: p.id == e.actor_id,
            order_by: [desc: e.as_of, desc: e.id],
            limit: 20,
            select: %{
              id: e.id,
              as_of: e.as_of,
              campaign: c.name,
              actor: p.display_name,
              snapshot: e.snapshot,
              version: e.version,
              previous_evaluation_id: e.previous_evaluation_id,
              correction_reason: e.correction_reason,
              campaign_metadata: e.campaign_metadata
            }
        )

      {:ok,
       %{
         campaigns: campaigns,
         total_xp: xp,
         level: Adventure.level(xp),
         ledger: ledger,
         evaluations: evaluations
       }}
    else
      {:error, :disabled}
    end
  end

  def create(attrs) do
    if Adventure.enabled?(),
      do: %Campaign{} |> Campaign.changeset(attrs) |> Repo.insert(),
      else: {:error, :disabled}
  end

  def create_historical(attrs, profile_id, opts \\ []) do
    if Adventure.enabled?() do
      snapshot_transaction(fn ->
        actor = actor!(profile_id)
        attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

        campaign =
          case %Campaign{}
               |> Campaign.changeset(Map.put(attrs, "rules_version", "season_v1"))
               |> Repo.insert() do
            {:ok, campaign} -> campaign
            {:error, changeset} -> Repo.rollback(changeset)
          end

        campaign |> historical_locked(actor, opts) |> refresh()
      end)
    else
      {:error, :disabled}
    end
  end

  def archive_historical(id, profile_id, confirmed) do
    if confirmed == true do
      action(id, fn campaign -> historical_locked(campaign, actor!(profile_id), []) end, true)
    else
      {:error, :confirmation_required}
    end
  end

  def update(id, attrs) do
    action(id, fn campaign ->
      if campaign.status != "draft", do: Repo.rollback(:immutable_campaign)

      case campaign |> Campaign.changeset(attrs) |> Repo.update() do
        {:ok, updated} -> updated
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def activate(id, profile_id, confirmed) do
    if confirmed == true do
      action(id, fn campaign ->
        profile = actor!(profile_id)

        cond do
          campaign.status == "active" ->
            campaign

          campaign.status != "draft" ->
            Repo.rollback(:immutable_campaign)

          Date.compare(campaign.ends_on, Stays.today()) == :lt ->
            Repo.rollback(:past_campaign)

          true ->
            changeset =
              Ecto.Changeset.change(campaign,
                status: "active",
                activated_at: now(),
                activated_by_id: profile.id
              )
              |> Ecto.Changeset.unique_constraint(:status)

            case Repo.update(changeset) do
              {:ok, active} -> active
              {:error, changeset} -> Repo.rollback(changeset)
            end
        end
      end)
    else
      {:error, :confirmation_required}
    end
  end

  def evaluate(id, profile_id, opts \\ []) do
    action(
      id,
      fn campaign ->
        actor = actor!(profile_id)

        if campaign.rules_version == "season_v1" and campaign.status == "closed" and
             is_nil(correction_reason(opts)) do
          Repo.rollback(:correction_reason_required)
        end

        evaluate_locked(campaign, actor, opts)
      end,
      true
    )
  end

  def close(id, profile_id) do
    action(
      id,
      fn campaign ->
        actor = actor!(profile_id)
        if campaign.status == "draft", do: Repo.rollback(:inactive_campaign)

        if campaign.status == "closed" do
          campaign
        else
          closed =
            campaign
            |> Ecto.Changeset.change(status: "closed", closed_at: now())
            |> Repo.update!()

          evaluate_locked(closed, actor, [])
        end
      end,
      true
    )
  end

  defp historical_locked(campaign, actor, opts) do
    cond do
      campaign.rules_version != "season_v1" ->
        Repo.rollback(:unsupported_rules)

      campaign.status == "closed" and campaign.historical ->
        campaign

      campaign.status != "draft" ->
        Repo.rollback(:immutable_campaign)

      Date.compare(campaign.ends_on, Stays.today()) != :lt ->
        Repo.rollback(:not_past_campaign)

      true ->
        campaign
        |> Ecto.Changeset.change(status: "closed", closed_at: now(), historical: true)
        |> Repo.update!()
        |> evaluate_locked(actor, opts)
    end
  end

  defp evaluate_locked(campaign, actor, opts) do
    if campaign.status == "draft", do: Repo.rollback(:inactive_campaign)

    case campaign.rules_version do
      "stays_v1" -> evaluate_legacy_locked(campaign, actor)
      "season_v1" -> evaluate_season_locked(campaign, actor, opts)
      _ -> Repo.rollback(:unsupported_rules)
    end
  end

  defp evaluate_season_locked(campaign, actor, opts) do
    reason = correction_reason(opts)

    if is_binary(reason) and String.length(reason) > 1000,
      do: Repo.rollback(:correction_reason_too_long)

    as_of = Keyword.get(opts, :as_of, DateTime.utc_now())
    source_opts = [as_of: as_of]

    sources =
      %{
        "stays" => Stays.evaluate(campaign, source_opts),
        "bar" => Bar.evaluate(campaign, source_opts),
        "billing" => Billing.evaluate(campaign, source_opts)
      }
      |> Map.new(fn {key, result} ->
        case result do
          {:error, reason} -> Repo.rollback(reason)
          result -> {key, source_metadata(result)}
        end
      end)

    previous =
      if campaign.last_evaluation_id, do: Repo.get!(Evaluation, campaign.last_evaluation_id)

    version = if previous, do: previous.version + 1, else: 1

    metadata =
      campaign
      |> Map.from_struct()
      |> Map.take(Campaign.__schema__(:fields))
      |> json_snapshot()

    stays = sources["stays"]

    snapshot =
      stays["metrics"]
      |> Map.merge(stays["evidence"])
      |> Map.merge(%{
        "as_of" => DateTime.to_iso8601(as_of),
        "rules_version" => "season_v1",
        "definition_version" => 1,
        "source_consistency" => "transaction_snapshot",
        "sources" => sources,
        "campaign" => metadata,
        "evaluation_version" => version,
        "previous_evaluation_id" => campaign.last_evaluation_id,
        "correction_reason" => reason,
        "completeness" =>
          if(
            Enum.all?(sources, fn {_, source} ->
              source["quality"]["completeness"] == "complete"
            end),
            do: "complete",
            else: "partial"
          )
      })

    evaluation =
      Repo.insert!(%Evaluation{
        campaign_id: campaign.id,
        actor_id: actor.id,
        snapshot: snapshot,
        as_of: %{as_of | microsecond: {elem(as_of.microsecond, 0), 6}},
        version: version,
        previous_evaluation_id: campaign.last_evaluation_id,
        correction_reason: reason,
        campaign_metadata: metadata
      })

    campaign |> Ecto.Changeset.change(last_evaluation_id: evaluation.id) |> Repo.update!()
  end

  defp source_metadata(source) do
    source = json_snapshot(source)

    metrics =
      Map.new(source["metrics"], fn {key, _value} ->
        quality = get_in(source, ["quality", "metrics", key]) || %{}
        as_of_on = source["evidence"]["as_of_on"] || source["evidence"]["cutoff_on"]
        period = Map.take(source["evidence"], ["starts_on", "ends_on"])
        settlement = String.starts_with?(key, "settlement_") or key == "personal_accounts_count"

        unit =
          cond do
            String.ends_with?(key, "_amount") -> "CZK"
            key == "occupancy_percent" -> "percent"
            String.contains?(key, "bednights") -> "bednights"
            true -> "count"
          end

        {key,
         Map.merge(
           %{
             "source" => source["source"],
             "definition_version" => source["definition_version"],
             "as_of" => source["as_of"],
             "unit" => unit,
             "period" => Map.put(period, "as_of_on", as_of_on),
             "time_basis" => if(settlement, do: "departure_cohort", else: "season_period"),
             "cohort_period" => if(settlement, do: period),
             "recorded_through_on" => as_of_on,
             "source_date_range" => %{
               "starts_on" =>
                 if(settlement and unit == "CZK", do: nil, else: period["starts_on"]),
               "ends_on" =>
                 if(settlement and unit == "CZK",
                   do: as_of_on,
                   else: min(period["ends_on"], as_of_on)
                 )
             },
             "completeness" => source["quality"]["completeness"]
           },
           quality
         )}
      end)

    Map.put(source, "metric_metadata", metrics)
  end

  defp json_snapshot(value), do: value |> Jason.encode!() |> Jason.decode!()

  defp correction_reason(opts) do
    case Keyword.get(opts, :correction_reason, Keyword.get(opts, :reason)) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          reason -> reason
        end

      _ ->
        nil
    end
  end

  defp evaluate_legacy_locked(campaign, actor) do
    snapshot = Stays.snapshot(campaign)

    evaluation =
      Repo.insert!(%Evaluation{
        campaign_id: campaign.id,
        actor_id: actor.id,
        snapshot: snapshot,
        as_of: DateTime.from_iso8601(snapshot["as_of"]) |> elem(1)
      })

    unlocks =
      Repo.all(from u in Unlock, where: u.campaign_id == ^campaign.id) |> Map.new(&{&1.code, &1})

    for definition <- @achievements do
      qualifies = snapshot["eligible_completed_stays"] >= definition.required
      existing = unlocks[definition.code]

      cond do
        qualifies and is_nil(existing) and snapshot["completeness"] == "complete" ->
          unlock =
            Repo.insert!(%Unlock{
              campaign_id: campaign.id,
              code: definition.code,
              rules_version: campaign.rules_version,
              xp: definition.xp,
              unlocked_at: now(),
              evidence:
                Map.put(
                  snapshot,
                  "achievement_definition",
                  Map.new(definition, fn {key, value} -> {Atom.to_string(key), value} end)
                )
            })

          Repo.insert!(%XpTransaction{
            recipient_type: "shared",
            unlock_id: unlock.id,
            award_key: "unlock:" <> unlock.id,
            amount: definition.xp,
            reason: definition.title,
            attribution: "automatic"
          })

        not qualifies and not is_nil(existing) and existing.status == "unlocked" and
            snapshot["completeness"] == "complete" ->
          existing
          |> Ecto.Changeset.change(
            status: "revoked",
            revoked_at: now(),
            revocation_evidence: snapshot
          )
          |> Repo.update!()

          original =
            Repo.one!(
              from x in XpTransaction,
                where: x.unlock_id == ^existing.id and is_nil(x.reverses_id)
            )

          Repo.insert!(%XpTransaction{
            recipient_type: "shared",
            unlock_id: existing.id,
            reverses_id: original.id,
            award_key: "reverse:" <> original.id,
            amount: -original.amount,
            reason: "Oprava pobytových dat: " <> definition.title,
            attribution: "automatic"
          })

        true ->
          :ok
      end
    end

    campaign |> Ecto.Changeset.change(last_evaluation_id: evaluation.id) |> Repo.update!()
  end

  defp action(id, fun, consistent_snapshot \\ false) do
    with true <- Adventure.enabled?(), {:ok, id} <- Ecto.UUID.cast(id) do
      transaction = if consistent_snapshot, do: &snapshot_transaction/1, else: &Repo.transaction/1

      transaction.(fn ->
        campaign = Repo.one(from c in Campaign, where: c.id == ^id, lock: "FOR UPDATE")
        if is_nil(campaign), do: Repo.rollback(:not_found)
        campaign |> fun.() |> refresh()
      end)
    else
      false -> {:error, :disabled}
      _ -> {:error, :not_found}
    end
  end

  defp snapshot_transaction(fun, attempts \\ 3) do
    nested = Repo.in_transaction?()

    if nested do
      case Repo.query!("SHOW transaction_isolation").rows do
        [[isolation]] when isolation in ["repeatable read", "serializable"] ->
          Repo.transaction(fun)

        _ ->
          {:error, :snapshot_isolation_required}
      end
    else
      try do
        Repo.transaction(fn ->
          # Postgrex does not implement an :isolation transaction option. SHOW
          # does not take a data snapshot; SET must precede the first data query.
          case Repo.query!("SHOW transaction_isolation").rows do
            [[isolation]] when isolation in ["repeatable read", "serializable"] -> :ok
            _ -> Repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
          end

          fun.()
        end)
      rescue
        error in Postgrex.Error ->
          if error.postgres[:code] == :serialization_failure and attempts > 1,
            do: snapshot_transaction(fun, attempts - 1),
            else: reraise(error, __STACKTRACE__)
      end
    end
  end

  defp refresh(%Campaign{rules_version: "season_v1"} = campaign),
    do: Repo.preload(campaign, [:last_evaluation, :unlocks], force: true)

  defp refresh(campaign), do: campaign

  defp actor!(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Profile{} = profile <- Repo.get_by(Profile, id: id, active: true) do
      profile
    else
      _ -> Repo.rollback(:invalid_profile)
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
