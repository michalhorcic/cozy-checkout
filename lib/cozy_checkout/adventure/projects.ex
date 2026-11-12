defmodule CozyCheckout.Adventure.Projects do
  @moduledoc "Season-independent Adventure plans. Budgets never represent accounting or cash."
  import Ecto.Query
  alias Ecto.Changeset
  alias CozyCheckout.{Adventure, Repo}
  alias CozyCheckout.Adventure.{Profile, Project, ProjectEvent, ProjectStage, Quest, Tasks}

  def world do
    if Adventure.enabled?() do
      counts =
        Repo.all(
          from p in Project,
            where: is_nil(p.archived_at) or p.status == "accepted",
            group_by: [p.area, p.status],
            select: {p.area, p.status, count(p.id)}
        )

      projects =
        Repo.all(
          from p in Project,
            where: is_nil(p.archived_at) or p.status == "accepted",
            order_by: [desc: p.updated_at, desc: p.id],
            limit: 100
        )

      %{counts: counts, projects: projects}
    else
      %{counts: [], projects: []}
    end
  end

  def chronicle(page \\ 0) when is_integer(page) and page >= 0 do
    if Adventure.enabled?() do
      Repo.all(
        from p in Project,
          where: p.status == "accepted",
          order_by: [desc: fragment("?->>'confirmed_at'", p.acceptance), desc: p.id],
          offset: ^(page * 20),
          limit: 21
      )
    else
      []
    end
  end

  def list(search \\ "", focus_id \\ nil) when is_binary(search) do
    if Adventure.enabled?() do
      search = String.slice(String.trim(search), 0, 200)

      filter =
        if valid_id?(focus_id),
          do: dynamic([p], p.id == ^focus_id),
          else: dynamic([p], fragment("strpos(lower(?), lower(?)) > 0", p.title, ^search))

      projects =
        Repo.all(
          from p in Project,
            where: ^filter,
            order_by: [desc: p.inserted_at, desc: p.id],
            limit: 100
        )

      ids = Enum.map(projects, & &1.id)

      stages =
        Repo.all(
          from s in ProjectStage,
            join: q in Quest,
            on: q.id == s.quest_id,
            where: s.project_id in ^ids and is_nil(s.archived_at),
            order_by: [asc: s.position],
            select: {s, q}
        )

      grouped = Enum.group_by(stages, fn {s, _} -> s.project_id end)
      Enum.map(projects, &%{project: &1, stages: Map.get(grouped, &1.id, [])})
    else
      []
    end
  end

  def history(id) do
    if Adventure.enabled?() and valid_id?(id),
      do:
        Repo.all(
          from e in ProjectEvent,
            where: e.project_id == ^id,
            order_by: [desc: e.version],
            limit: 50
        ),
      else: []
  end

  def search_quests(search) when is_binary(search) do
    if Adventure.enabled?() and String.trim(search) != "" do
      search = String.slice(String.trim(search), 0, 200)

      Repo.all(
        from q in Quest,
          where:
            q.managed and is_nil(q.archived_at) and q.status != "cancelled" and
              fragment("strpos(lower(?->>'title'), lower(?)) > 0", q.definition_snapshot, ^search),
          order_by: [desc: q.inserted_at, desc: q.id],
          limit: 30
      )
    else
      []
    end
  end

  def create(actor_id, attrs, request_key) do
    action(actor_id, fn actor ->
      unless valid_id?(request_key), do: Repo.rollback(:invalid_request)

      case Repo.get_by(Project, request_key: request_key) do
        nil ->
          project =
            %Project{request_key: request_key}
            |> Project.changeset(attrs)
            |> Changeset.unique_constraint(:request_key)
            |> save!(:insert)

          audit!(project, actor.id, "created")

        project ->
          project
      end
    end)
  end

  def update(actor_id, id, attrs) do
    action(actor_id, fn actor ->
      project = locked!(id)
      editable!(project)
      changeset = Project.changeset(project, attrs)
      unless changeset.valid?, do: Repo.rollback(changeset)

      if changeset.changes == %{},
        do: project,
        else: changeset |> save!(:update) |> record!(actor.id, "edited")
    end)
  end

  def add_stage(actor_id, id, quest_id, output) do
    action(actor_id, fn actor ->
      project = locked!(id)
      editable!(project)
      unless valid_id?(quest_id), do: Repo.rollback(:not_found)
      stages = Repo.all(from s in ProjectStage, where: s.project_id == ^project.id)

      case Enum.find(stages, &(&1.quest_id == quest_id)) do
        nil ->
          quest =
            Repo.one(
              from q in Quest,
                where:
                  q.id == ^quest_id and q.managed and is_nil(q.archived_at) and
                    q.status != "cancelled"
            )

          unless quest, do: Repo.rollback(:not_found)

          output =
            if is_nil(output) or (is_binary(output) and String.trim(output) == ""),
              do: quest.definition_snapshot["title"],
              else: output

          stage =
            %ProjectStage{
              project_id: project.id,
              quest_id: quest.id,
              position: length(stages) + 1,
              quest_snapshot: quest.definition_snapshot
            }
            |> Changeset.cast(%{output: output}, [:output])
            |> Changeset.validate_required([:output])
            |> Changeset.validate_length(:output, max: 2000)
            |> save!(:insert)

          record!(project, actor.id, "stage_added", %{
            "stage_id" => stage.id,
            "quest_id" => quest.id,
            "output" => output,
            "quest_snapshot" => quest.definition_snapshot
          })

        %ProjectStage{archived_at: archived_at} = stage when not is_nil(archived_at) ->
          stage |> Changeset.change(archived_at: nil) |> save!(:update)

          record!(project, actor.id, "stage_restored", %{
            "stage_id" => stage.id,
            "output" => stage.output
          })

        _ ->
          project
      end
    end)
  end

  def create_stage(actor_id, id, attrs) do
    action(actor_id, fn actor ->
      project = locked!(id)
      editable!(project)

      # Reuse Tasks validation and snapshots inside the same database transaction.
      with {:ok, quest} <- Tasks.create(actor.id, attrs),
           {:ok, updated} <- add_stage(actor.id, project.id, quest.id, attrs["output"]) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def remove_stage(actor_id, id, stage_id) do
    action(actor_id, fn actor ->
      project = locked!(id)
      editable!(project)
      unless valid_id?(stage_id), do: Repo.rollback(:not_found)

      stage =
        Repo.one(from s in ProjectStage, where: s.project_id == ^project.id and s.id == ^stage_id)

      unless stage, do: Repo.rollback(:not_found)

      if stage.archived_at do
        project
      else
        stage |> Changeset.change(archived_at: now()) |> save!(:update)

        record!(project, actor.id, "stage_removed", %{
          "stage_id" => stage.id,
          "output" => stage.output,
          "quest_id" => stage.quest_id
        })
      end
    end)
  end

  def update_stage(actor_id, id, stage_id, output) do
    action(actor_id, fn actor ->
      project = locked!(id)
      editable!(project)
      unless valid_id?(stage_id), do: Repo.rollback(:not_found)

      stage =
        Repo.one(
          from s in ProjectStage,
            where: s.project_id == ^project.id and s.id == ^stage_id and is_nil(s.archived_at)
        )

      unless stage, do: Repo.rollback(:not_found)

      changeset =
        stage
        |> Changeset.cast(%{output: output}, [:output])
        |> Changeset.validate_required([:output])
        |> Changeset.validate_length(:output, max: 2000)

      unless changeset.valid?, do: Repo.rollback(changeset)

      if changeset.changes == %{} do
        project
      else
        updated = save!(changeset, :update)

        record!(project, actor.id, "stage_edited", %{
          "stage_id" => stage.id,
          "output" => updated.output,
          "previous_output" => stage.output
        })
      end
    end)
  end

  def transition(actor_id, id, target) do
    action(actor_id, fn actor ->
      project = locked!(id)

      allowed = %{
        "idea" => ["active", "ready", "cancelled"],
        "ready" => ["active", "idea", "approved", "cancelled"],
        "approved" => ["active", "paused", "cancelled"],
        "active" => ["paused", "cancelled"],
        "paused" => ["active", "approved", "cancelled"]
      }

      cond do
        project.status == target ->
          project

        not is_nil(project.archived_at) or target not in Map.get(allowed, project.status, []) ->
          Repo.rollback(:invalid_transition)

        true ->
          project
          |> Changeset.change(status: target)
          |> save!(:update)
          |> record!(actor.id, "status_changed")
      end
    end)
  end

  def accept(actor_id, id, attrs) do
    action(actor_id, fn actor ->
      project = locked!(id)

      cond do
        project.status == "accepted" ->
          project

        project.status != "active" or not is_nil(project.archived_at) ->
          Repo.rollback(:invalid_transition)

        attrs["confirmed"] != "true" ->
          Repo.rollback(:confirmation_required)

        true ->
          # The project lock freezes its stages; a single ordered batch locks linked quests.
          stages =
            Repo.all(
              from s in ProjectStage,
                join: q in Quest,
                on: s.quest_id == q.id,
                where: s.project_id == ^project.id and is_nil(s.archived_at),
                order_by: [asc: q.id],
                select: {s, q},
                lock: "FOR SHARE"
            )

          if stages == [] or Enum.any?(stages, fn {_, q} -> q.status != "completed" end),
            do: Repo.rollback(:unfinished_stages)

          ids = attrs["contributors"]

          unless is_list(ids) and ids != [] and Enum.all?(ids, &valid_id?/1),
            do: Repo.rollback(:contributors_required)

          ids = Enum.sort(Enum.uniq(ids))
          found = Repo.all(from p in Profile, where: p.id in ^ids and p.active, select: p.id)
          if Enum.sort(found) != ids, do: Repo.rollback(:contributors_required)
          result = attrs["result"] || ""

          unless is_binary(result) and String.length(result) <= 5000,
            do: Repo.rollback(:invalid_result)

          acceptance = %{
            "actor_id" => actor.id,
            "contributors" => ids,
            "confirmed_at" => DateTime.to_iso8601(now()),
            "result" => String.trim(result),
            "attribution" => "self_selected",
            "stages" =>
              Enum.map(stages, fn {s, q} ->
                %{
                  "id" => s.id,
                  "quest_id" => q.id,
                  "output" => s.output,
                  "definition" => q.definition_snapshot,
                  "evidence" => q.evidence
                }
              end)
          }

          project
          |> Changeset.change(status: "accepted", acceptance: acceptance)
          |> save!(:update)
          |> record!(actor.id, "accepted")
          |> Map.put(:newly_accepted, true)
      end
    end)
  end

  def archive(actor_id, id) do
    action(actor_id, fn actor ->
      project = locked!(id)

      cond do
        project.archived_at ->
          project

        project.status not in ["accepted", "cancelled"] ->
          Repo.rollback(:invalid_transition)

        true ->
          project
          |> Changeset.change(archived_at: now())
          |> save!(:update)
          |> record!(actor.id, "archived")
      end
    end)
  end

  defp action(actor_id, fun) do
    if Adventure.enabled?() do
      Repo.transaction(fn ->
        unless valid_id?(actor_id), do: Repo.rollback(:invalid_profile)

        actor =
          Repo.one(from p in Profile, where: p.id == ^actor_id and p.active, lock: "FOR UPDATE")

        unless actor, do: Repo.rollback(:invalid_profile)
        fun.(actor)
      end)
    else
      {:error, :disabled}
    end
  end

  defp locked!(id) do
    unless valid_id?(id), do: Repo.rollback(:not_found)

    Repo.one(from p in Project, where: p.id == ^id, lock: "FOR UPDATE") ||
      Repo.rollback(:not_found)
  end

  defp editable!(project) do
    if project.status not in ["idea", "ready"] or not is_nil(project.archived_at),
      do: Repo.rollback(:immutable_project)
  end

  defp record!(project, actor, action, extra \\ %{}) do
    project
    |> Changeset.change(version: project.version + 1)
    |> save!(:update)
    |> audit!(actor, action, extra)
  end

  defp audit!(project, actor, action, extra \\ %{}) do
    snapshot =
      project
      |> Map.from_struct()
      |> Map.drop([:__meta__, :owner])
      |> Jason.encode!()
      |> Jason.decode!()

    %ProjectEvent{
      project_id: project.id,
      actor_id: actor,
      version: project.version,
      action: action,
      snapshot: Map.merge(snapshot, extra)
    }
    |> Changeset.change()
    |> save!(:insert)

    project
  end

  defp save!(changeset, operation) do
    case apply(Repo, operation, [changeset]) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp valid_id?(id), do: match?({:ok, _}, Ecto.UUID.cast(id))
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
