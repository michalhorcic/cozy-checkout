defmodule CozyCheckout.Adventure do
  @moduledoc """
  Optional hobby game. Owns only adventure_* records; never calls operational
  write APIs. Future operational reads belong in Adventure.Sources adapters.
  Profiles are self-selected inside the shared admin session, not identities.
  """
  import Ecto.Query
  alias Ecto.Multi
  alias CozyCheckout.Repo
  alias CozyCheckout.Adventure.{Catalog, Profile, Quest, XpTransaction}

  def enabled?, do: Application.get_env(:cozy_checkout, :adventure_enabled, false) == true
  def catalog, do: Catalog.quests()

  @doc "Explicit, repeatable setup; never runs from application startup or render."
  def initialize do
    if enabled?() do
      Repo.transaction(fn ->
        for {slug, name} <- [{"michal", "Michal"}, {"lucka", "Lucka"}] do
          Repo.insert!(%Profile{slug: slug, display_name: name},
            on_conflict: :nothing,
            conflict_target: :slug
          )
        end

        :ok
      end)
    else
      {:error, :disabled}
    end
  end

  def list_profiles do
    if enabled?(),
      do: Repo.all(from p in Profile, where: p.active, order_by: p.slug),
      else: []
  end

  def dashboard(profile_id) do
    if enabled?() do
      profiles = list_profiles()
      profile = Enum.find(profiles, &(&1.id == profile_id))

      quests =
        if profile,
          do:
            Repo.all(
              from q in Quest,
                where: q.profile_id == ^profile.id,
                order_by: [asc: q.status, desc: q.inserted_at, desc: q.id],
                limit: 100
            ),
          else: []

      total =
        if profile,
          do:
            Repo.one(
              from x in XpTransaction,
                where: x.profile_id == ^profile.id,
                select: coalesce(sum(x.amount), 0)
            ),
          else: 0

      ledger =
        if profile,
          do:
            Repo.all(
              from x in XpTransaction,
                where: x.profile_id == ^profile.id,
                order_by: [desc: x.inserted_at, desc: x.id],
                limit: 20
            ),
          else: []

      {:ok,
       %{
         profiles: profiles,
         profile: profile,
         quests: quests,
         total_xp: total,
         level: level(total),
         ledger: ledger
       }}
    else
      {:error, :disabled}
    end
  end

  @doc "Integer arithmetic also works beyond floating point precision."
  def level(xp) when is_integer(xp) and xp >= 0 do
    upper = Stream.iterate(2, &(&1 * 2)) |> Enum.find(&(threshold(&1) > xp))
    find_level(xp, div(upper, 2), upper)
  end

  def level(xp) when is_integer(xp), do: 1
  defp threshold(level), do: div(100 * (level - 1) * level, 2)
  defp find_level(_xp, low, high) when high - low <= 1, do: low

  defp find_level(xp, low, high) do
    mid = div(low + high, 2)
    if threshold(mid) <= xp, do: find_level(xp, mid, high), else: find_level(xp, low, mid)
  end

  @doc "ISO week in Prague, using PostgreSQL's installed timezone database."
  def weekly_period(at \\ DateTime.utc_now()) do
    date =
      Repo.one(
        from p in fragment("SELECT timezone('Europe/Prague', ?::timestamptz)::date AS day", ^at),
          select: type(field(p, :day), :date)
      )

    "week:" <> Date.to_iso8601(Date.beginning_of_week(date))
  end

  def activate_quest(profile_id, code) do
    with true <- enabled?(),
         %{} = definition <- Catalog.fetch(code) do
      mutate(profile_id, fn profile ->
        period = if definition.cadence == "weekly", do: weekly_period(), else: "once"
        existing = Repo.get_by(Quest, profile_id: profile.id, code: code, period_key: period)

        cond do
          existing ->
            existing

          Repo.aggregate(
            from(q in Quest, where: q.profile_id == ^profile.id and q.status == "active"),
            :count
          ) >= 3 ->
            Repo.rollback(:active_limit)

          true ->
            snapshot = Map.new(definition, fn {key, value} -> {Atom.to_string(key), value} end)

            Repo.insert!(%Quest{
              profile_id: profile.id,
              code: code,
              version: definition.version,
              period_key: period,
              definition_snapshot: snapshot
            })
        end
      end)
    else
      false -> {:error, :disabled}
      _ -> {:error, :unknown_quest}
    end
  end

  def complete_manual_quest(profile_id, quest_id, note) do
    with true <- enabled?(),
         {:ok, quest_id} <- Ecto.UUID.cast(quest_id) do
      # One Multi transaction, with a profile lock shared by every game mutation.
      # This serializes the active limit, retries, completion and corrections.
      multi =
        Multi.new()
        |> Multi.run(:profile, fn _, _ -> lock_profile(profile_id) end)
        |> Multi.run(:quest, fn _, %{profile: profile} ->
          quest =
            Repo.one(
              from q in Quest,
                where: q.id == ^quest_id and q.profile_id == ^profile.id,
                lock: "FOR UPDATE"
            )

          cond do
            is_nil(quest) ->
              {:error, :not_found}

            quest.status == "completed" ->
              {:ok, quest}

            not valid_note?(note) ->
              {:error, :evidence_required}

            true ->
              quest
              |> Ecto.Changeset.change(
                status: "completed",
                completed_at: now(),
                evidence: %{
                  "note" => String.trim(note),
                  "actor_profile_id" => profile.id,
                  "attribution" => "self_selected",
                  "confirmed_at" => DateTime.to_iso8601(now())
                }
              )
              |> Repo.update()
          end
        end)
        |> Multi.run(:award, fn _, %{quest: quest} ->
          key = "quest:" <> quest.id

          case Repo.get_by(XpTransaction, award_key: key) do
            nil ->
              %XpTransaction{
                profile_id: quest.profile_id,
                quest_id: quest.id,
                award_key: key,
                amount: quest.definition_snapshot["xp"],
                reason: quest.definition_snapshot["title"],
                attribution: "self_selected"
              }
              |> Ecto.Changeset.change()
              |> Ecto.Changeset.validate_required([:amount, :reason])
              |> Ecto.Changeset.validate_number(:amount, greater_than: 0)
              |> Repo.insert()

            award ->
              {:ok, award}
          end
        end)

      case Repo.transaction(multi) do
        {:ok, %{quest: quest}} -> {:ok, quest}
        {:error, _, reason, _} -> {:error, reason}
      end
    else
      false -> {:error, :disabled}
      _ -> {:error, :not_found}
    end
  end

  @doc "Append an audited correction once; never edit or delete the original award."
  def reverse_award(profile_id, award_id, reason) do
    with true <- enabled?(),
         {:ok, award_id} <- Ecto.UUID.cast(award_id),
         true <- valid_note?(reason) do
      mutate(profile_id, fn profile ->
        award = Repo.get_by(XpTransaction, id: award_id, profile_id: profile.id)
        if is_nil(award) or award.amount <= 0, do: Repo.rollback(:not_found)

        Repo.get_by(XpTransaction, reverses_id: award.id) ||
          Repo.insert!(%XpTransaction{
            profile_id: profile.id,
            quest_id: award.quest_id,
            reverses_id: award.id,
            award_key: "reverse:" <> award.id,
            amount: -award.amount,
            reason: String.trim(reason),
            attribution: "self_selected"
          })
      end)
    else
      _ -> {:error, :invalid_correction}
    end
  end

  defp mutate(profile_id, fun) do
    Repo.transaction(fn ->
      case lock_profile(profile_id) do
        {:ok, profile} -> fun.(profile)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp lock_profile(profile_id) do
    with {:ok, id} <- Ecto.UUID.cast(profile_id),
         %Profile{} = profile <-
           Repo.one(from p in Profile, where: p.id == ^id and p.active, lock: "FOR UPDATE") do
      {:ok, profile}
    else
      _ -> {:error, :invalid_profile}
    end
  end

  defp valid_note?(note), do: is_binary(note) and String.length(String.trim(note)) in 10..1000
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
