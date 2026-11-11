defmodule CozyCheckout.Adventure.Campaigns do
  @moduledoc "Campaign lifecycle and game-only reconciliation. Operational reads use Sources.Stays."
  import Ecto.Query
  alias CozyCheckout.{Adventure, Repo}
  alias CozyCheckout.Adventure.{Campaign, Evaluation, Profile, Unlock, XpTransaction}
  alias CozyCheckout.Adventure.Sources.Stays

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
              snapshot: e.snapshot
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

  def evaluate(id, profile_id) do
    action(id, fn campaign -> evaluate_locked(campaign, actor!(profile_id)) end)
  end

  def close(id, profile_id) do
    action(id, fn campaign ->
      actor = actor!(profile_id)
      if campaign.status == "draft", do: Repo.rollback(:inactive_campaign)

      if campaign.status == "closed" do
        campaign
      else
        closed =
          campaign |> Ecto.Changeset.change(status: "closed", closed_at: now()) |> Repo.update!()

        evaluate_locked(closed, actor)
      end
    end)
  end

  defp evaluate_locked(campaign, actor) do
    if campaign.status == "draft", do: Repo.rollback(:inactive_campaign)
    if campaign.rules_version != "stays_v1", do: Repo.rollback(:unsupported_rules)
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

  defp action(id, fun) do
    with true <- Adventure.enabled?(), {:ok, id} <- Ecto.UUID.cast(id) do
      Repo.transaction(fn ->
        campaign = Repo.one(from c in Campaign, where: c.id == ^id, lock: "FOR UPDATE")
        if is_nil(campaign), do: Repo.rollback(:not_found)
        fun.(campaign)
      end)
    else
      false -> {:error, :disabled}
      _ -> {:error, :not_found}
    end
  end

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
