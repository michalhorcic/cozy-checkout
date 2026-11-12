defmodule CozyCheckout.Adventure.Tasks do
  @moduledoc "Managed tasks. Assignment, completion actor and XP recipient are separate."
  import Ecto.Query
  alias Ecto.Changeset
  alias CozyCheckout.{Adventure, Repo}
  alias CozyCheckout.Adventure.{Profile, Quest, XpTransaction}

  def list(profile_id, filters \\ %{}) do
    if Adventure.enabled?() do
      profile_id =
        case Ecto.UUID.cast(profile_id) do
          {:ok, id} -> id
          _ -> nil
        end

      query =
        if filters["kind"] == "history",
          do: from(q in Quest),
          else: from(q in Quest, where: q.managed)

      query =
        if filters["kind"] == "one_off", do: where(query, [q], is_nil(q.template_id)), else: query

      query =
        case filters["scope"] do
          "mine" when is_binary(profile_id) ->
            where(query, [q], q.assigned_profile_id == ^profile_id or q.profile_id == ^profile_id)

          "mine" ->
            where(query, [q], false)

          "free" ->
            where(
              query,
              [q],
              q.scope == "personal" and is_nil(q.assigned_profile_id) and is_nil(q.profile_id)
            )

          "shared" ->
            where(query, [q], q.scope == "shared")

          _ ->
            query
        end

      query =
        case filters["status"] do
          "all" ->
            query

          "archived" ->
            where(query, [q], not is_nil(q.archived_at))

          status when status in ["waiting", "active", "completed", "cancelled"] ->
            where(query, [q], q.status == ^status and is_nil(q.archived_at))

          _ ->
            where(query, [q], q.status in ["waiting", "active"] and is_nil(q.archived_at))
        end

      query =
        if filters["category"] in Quest.categories(),
          do: where(query, [q], q.category == ^filters["category"]),
          else: query

      query =
        case filters["due"] do
          "overdue" -> where(query, [q], q.due_on < ^CozyCheckout.Adventure.Sources.Stays.today())
          "none" -> where(query, [q], is_nil(q.due_on))
          _ -> query
        end

      query =
        case filters["search"] do
          search when is_binary(search) and search != "" ->
            where(
              query,
              [q],
              fragment(
                "strpos(lower(?->>'title'), lower(?)) > 0",
                q.definition_snapshot,
                ^String.slice(search, 0, 200)
              )
            )

          _ ->
            query
        end

      query =
        if filters["kind"] == "history",
          do:
            order_by(query, [q], desc_nulls_last: q.completed_at, desc: q.inserted_at, desc: q.id),
          else: order_by(query, [q], asc_nulls_last: q.due_on, desc: q.inserted_at, desc: q.id)

      Repo.all(limit(query, 100))
    else
      []
    end
  end

  @doc "One game-only batch for the camp's waiting offers and active shared expeditions."
  def camp_quests do
    if Adventure.enabled?(),
      do:
        Repo.all(
          from q in Quest,
            where:
              q.managed and is_nil(q.archived_at) and
                (q.status == "waiting" or (q.scope == "shared" and q.status == "active")),
            order_by: [asc: q.status, asc_nulls_last: q.due_on, desc: q.inserted_at, desc: q.id],
            limit: 100
        ),
      else: []
  end

  def change(%Quest{} = task, attrs \\ %{}) do
    snapshot = task.definition_snapshot || %{}

    task = %{
      task
      | title: snapshot["title"],
        size: snapshot["size"] || "small",
        xp: snapshot["xp"]
    }

    Quest.task_changeset(task, attrs)
  end

  def create(actor_id, attrs) do
    action(actor_id, fn actor ->
      changeset =
        change(
          %Quest{
            managed: true,
            status: "waiting",
            created_by_id: actor.id,
            code: "task:" <> Ecto.UUID.generate(),
            version: 1,
            period_key: "once"
          },
          attrs
        )

      save_definition(changeset, actor, :insert)
    end)
  end

  def update(actor_id, id, attrs) do
    action(actor_id, fn actor ->
      task = task!(id)

      if task.status != "waiting" or not is_nil(task.archived_at) or not is_nil(task.template_id),
        do: Repo.rollback(:immutable_task)

      save_definition(change(task, attrs), actor, :update)
    end)
  end

  def start(actor_id, id) do
    action(actor_id, fn actor ->
      task = task!(id)

      cond do
        task.status == "active" ->
          task

        task.status != "waiting" or not is_nil(task.archived_at) ->
          Repo.rollback(:immutable_task)

        true ->
          if task.scope == "personal", do: ensure_slot!(actor.id)

          update!(task,
            status: "active",
            assigned_profile_id: if(task.scope == "personal", do: actor.id),
            evidence:
              Map.merge(task.evidence, %{
                "started_by_id" => actor.id,
                "started_at" => DateTime.to_iso8601(now()),
                "assignment_before_start" => task.assigned_profile_id
              })
          )
      end
    end)
  end

  def complete(actor_id, id, attrs \\ %{}) do
    action(actor_id, fn actor ->
      task = task!(id)

      cond do
        task.status == "completed" ->
          task

        task.status != "active" or not is_nil(task.archived_at) ->
          Repo.rollback(:immutable_task)

        true ->
          note = attrs["note"] || ""
          if not is_binary(note) or String.length(note) > 1000, do: Repo.rollback(:invalid_note)

          contributors =
            if task.scope == "shared", do: contributors!(attrs["contributors"]), else: []

          evidence =
            Map.merge(task.evidence, %{
              "actor_profile_id" => actor.id,
              "assigned_profile_id" => task.assigned_profile_id,
              "contributor_profile_ids" => contributors,
              "note" => String.trim(note),
              "attribution" => "self_selected",
              "confirmed_at" => DateTime.to_iso8601(now())
            })

          completed = update!(task, status: "completed", completed_at: now(), evidence: evidence)
          recipient = if task.scope == "shared", do: "shared", else: "profile"

          %XpTransaction{recipient_type: recipient, attribution: "self_selected"}
          |> Changeset.cast(
            %{
              profile_id: if(recipient == "profile", do: actor.id),
              quest_id: task.id,
              award_key: "quest:" <> task.id,
              amount: task.definition_snapshot["xp"],
              reason: task.definition_snapshot["title"]
            },
            [:profile_id, :quest_id, :award_key, :amount, :reason]
          )
          |> Changeset.validate_required([:quest_id, :award_key, :amount, :reason])
          |> Changeset.validate_number(:amount, greater_than: 0)
          |> persist!(:insert)

          completed
      end
    end)
  end

  def archive(actor_id, id) do
    action(actor_id, fn actor ->
      task = task!(id)

      if task.archived_at do
        task
      else
        update!(task,
          archived_at: now(),
          status: if(task.status == "completed", do: "completed", else: "cancelled"),
          evidence:
            Map.merge(task.evidence, %{
              "archived_by_id" => actor.id,
              "archived_at" => DateTime.to_iso8601(now())
            })
        )
      end
    end)
  end

  defp save_definition(changeset, actor, operation) do
    changeset =
      if Changeset.get_field(changeset, :scope) == "shared",
        do: Changeset.put_change(changeset, :assigned_profile_id, nil),
        else: changeset

    assigned_id = Changeset.get_field(changeset, :assigned_profile_id)

    if assigned_id && changeset.valid? &&
         not Repo.exists?(from p in Profile, where: p.id == ^assigned_id and p.active),
       do: Repo.rollback(:invalid_profile)

    xp =
      Changeset.get_field(changeset, :xp) ||
        %{"small" => 50, "medium" => 100, "large" => 250}[Changeset.get_field(changeset, :size)]

    snapshot = %{
      "title" => Changeset.get_field(changeset, :title),
      "xp" => xp,
      "size" => Changeset.get_field(changeset, :size),
      "cadence" => "once",
      "version" => 1
    }

    changeset
    |> Changeset.put_change(:definition_snapshot, snapshot)
    |> Changeset.put_change(
      :evidence,
      Map.merge(changeset.data.evidence, %{
        "last_edited_by_id" => actor.id,
        "last_edited_at" => DateTime.to_iso8601(now())
      })
    )
    |> persist!(operation)
  end

  defp contributors!(ids) when is_list(ids) do
    ids = Enum.uniq(ids)

    if ids == [] or Enum.any?(ids, &(not match?({:ok, _}, Ecto.UUID.cast(&1)))),
      do: Repo.rollback(:contributors_required)

    count = Repo.aggregate(from(p in Profile, where: p.id in ^ids and p.active), :count)
    if count != length(ids), do: Repo.rollback(:contributors_required)
    Enum.sort(ids)
  end

  defp contributors!(_), do: Repo.rollback(:contributors_required)

  defp ensure_slot!(id) do
    count =
      Repo.aggregate(
        from(q in Quest,
          where:
            q.status == "active" and
              ((q.managed and q.scope == "personal" and q.assigned_profile_id == ^id) or
                 (not q.managed and q.profile_id == ^id))
        ),
        :count
      )

    if count >= 3, do: Repo.rollback(:active_limit)
  end

  defp task!(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Quest{} = task <-
           Repo.one(from q in Quest, where: q.id == ^id and q.managed, lock: "FOR UPDATE") do
      task
    else
      _ -> Repo.rollback(:not_found)
    end
  end

  # The same profile lock as the legacy catalog serializes the personal slot limit.
  # The quest lock serializes completion by different actors and shared rewards.
  defp action(actor_id, fun) do
    if Adventure.enabled?() do
      Repo.transaction(fn ->
        with {:ok, id} <- Ecto.UUID.cast(actor_id),
             %Profile{} = actor <-
               Repo.one(from p in Profile, where: p.id == ^id and p.active, lock: "FOR UPDATE") do
          fun.(actor)
        else
          _ -> Repo.rollback(:invalid_profile)
        end
      end)
    else
      {:error, :disabled}
    end
  end

  defp update!(task, attrs), do: task |> Changeset.change(attrs) |> persist!(:update)

  defp persist!(changeset, operation) do
    case apply(Repo, operation, [changeset]) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
