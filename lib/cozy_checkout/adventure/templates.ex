defmodule CozyCheckout.Adventure.Templates do
  @moduledoc "Versioned templates and idempotent recurrence. All writes stay in Adventure."
  import Ecto.Query
  alias Ecto.Changeset
  alias CozyCheckout.{Adventure, Repo}

  alias CozyCheckout.Adventure.{
    Catalog,
    Profile,
    Quest,
    Recurrence,
    TaskTemplate,
    TemplateVersion
  }

  alias CozyCheckout.Adventure.Sources.{Guests, Stays}

  @examples [
    {"rooms", "Připravit pokoje", "weekly", "Provoz"},
    {"cleaning", "Větší úklid", "weekly", "Úklid"},
    {"menu", "Připravit jídelníček", "weekly", "Kuchyně"},
    {"shopping", "Nakoupit na příští skupinu", "weekly", "Kuchyně"},
    {"cooking", "Uvařit potřebná jídla", "daily", "Kuchyně"},
    {"common", "Zkontrolovat a uklidit společné prostory", "daily", "Úklid"},
    {"bar", "Zkontrolovat a doplnit bar", "daily", "Bar"}
  ]

  def list do
    if Adventure.enabled?(),
      do: Repo.all(from t in TaskTemplate, order_by: [asc: t.status, asc: t.title, asc: t.id]),
      else: []
  end

  def history do
    if Adventure.enabled?(),
      do:
        Repo.all(
          from v in TemplateVersion, order_by: [desc: v.inserted_at, desc: v.id], limit: 50
        ),
      else: []
  end

  def refresh(actor_id) do
    action(actor_id, fn _ ->
      case generate() do
        {:ok, results} -> results
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def change(template, attrs \\ %{}) do
    key = if Enum.any?(Map.keys(attrs), &is_binary/1), do: "xp", else: :xp
    size_key = if is_binary(key), do: "size", else: :size
    days_key = if is_binary(key), do: "weekdays", else: :weekdays

    attrs =
      case Map.fetch(attrs, days_key) do
        {:ok, days} when is_list(days) -> Map.put(attrs, days_key, Enum.reject(days, &(&1 == "")))
        _ -> attrs
      end

    reward =
      Map.get(attrs, key, if(template.__meta__.state == :built, do: nil, else: template.xp))

    attrs =
      if reward in [nil, ""],
        do:
          Map.put(
            attrs,
            key,
            %{"small" => 50, "medium" => 100, "large" => 250}[
              Map.get(attrs, size_key, template.size)
            ]
          ),
        else: attrs

    TaskTemplate.changeset(template, attrs)
  end

  def create(actor_id, attrs) do
    action(actor_id, fn actor ->
      template = persist!(change(%TaskTemplate{created_by_id: actor.id}, attrs), :insert)
      validate_assignment!(template)
      record_version!(template, actor.id)
      template
    end)
  end

  def update(actor_id, id, attrs) do
    action(actor_id, fn actor ->
      template = lock!(id)
      if template.status == "archived", do: Repo.rollback(:immutable_template)
      changeset = change(template, attrs)

      changeset =
        if template.legacy_code && Changeset.get_field(changeset, :cadence) != template.cadence,
          do:
            Changeset.add_error(
              changeset,
              :cadence,
              "u původního katalogu zachovej frekvenci; založ novou šablonu"
            ),
          else: changeset

      changeset =
        if template.legacy_code &&
             length(List.wrap(Changeset.get_field(changeset, :weekdays))) != 1,
           do:
             Changeset.add_error(
               changeset,
               :weekdays,
               "původní týdenní quest má jeden termín týdně"
             ),
           else: changeset

      updated = changeset |> Changeset.change(version: template.version + 1) |> persist!(:update)
      validate_assignment!(updated)
      # Schedule edits apply from today onward; old occurrences keep their snapshot.
      updated =
        updated
        |> Changeset.change(next_due_on: Recurrence.next(updated, Stays.today()))
        |> persist!(:update)

      record_version!(updated, actor.id)
      updated
    end)
  end

  def set_status(actor_id, id, status, open_choice) do
    action(actor_id, fn actor ->
      template = lock!(id)

      unless status in ["active", "paused", "archived"] and open_choice in ["keep", "cancel"],
        do: Repo.rollback(:open_choice_required)

      if template.status == "archived", do: Repo.rollback(:immutable_template)
      if status == "active" and open_choice != "keep", do: Repo.rollback(:open_choice_required)
      if status == "active", do: validate_assignment!(template)

      if status != "active" and open_choice == "cancel" do
        for task <- open_tasks(template, true) do
          task
          |> Changeset.change(
            status: "cancelled",
            archived_at: now(),
            evidence:
              Map.merge(
                task.evidence,
                %{
                  "archived_by_id" => actor.id,
                  "archived_at" => DateTime.to_iso8601(now()),
                  "template_status" => status
                }
              )
          )
          |> persist!(:update)
        end
      end

      updated =
        template
        |> Changeset.change(
          status: status,
          version: template.version + 1,
          next_due_on:
            if(status == "active",
              do: Recurrence.next(template, Stays.today()),
              else: template.next_due_on
            )
        )
        |> persist!(:update)

      record_version!(updated, actor.id, %{"open_occurrence_choice" => open_choice})
      updated
    end)
  end

  def add_examples(actor_id) do
    action(actor_id, fn actor ->
      today = Stays.today()

      for {code, title, cadence, category} <- @examples do
        seed!(
          %TaskTemplate{
            title: title,
            cadence: cadence,
            category: category,
            starts_on: today,
            next_due_on:
              Recurrence.next(%TaskTemplate{starts_on: today, cadence: cadence}, today),
            seed_key: "example:" <> code,
            created_by_id: actor.id
          },
          actor.id
        )
      end

      :ok
    end)
  end

  # Explicit initialization and the migration use the same stable per-profile seed identity.
  @doc false
  def seed_legacy(profiles) do
    if Adventure.enabled?(), do: seed_legacy_enabled(profiles), else: {:error, :disabled}
  end

  defp seed_legacy_enabled(profiles) do
    today = Stays.today()

    for profile <- profiles, definition <- Catalog.quests() do
      seed!(
        %TaskTemplate{
          title: definition.title,
          xp: definition.xp,
          size: %{50 => "small", 100 => "medium", 250 => "large"}[definition.xp],
          cadence: definition.cadence,
          assigned_profile_id: profile.id,
          legacy_profile_id: profile.id,
          starts_on: today,
          next_due_on: today,
          legacy_code: definition.code,
          seed_key: "legacy:#{profile.id}:#{definition.code}"
        },
        nil
      )
    end

    :ok
  end

  defp seed!(template, actor_id) do
    timestamp = now()

    attrs =
      template
      |> Map.from_struct()
      |> Map.take([
        :title,
        :description,
        :category,
        :priority,
        :scope,
        :assigned_profile_id,
        :legacy_profile_id,
        :size,
        :xp,
        :cadence,
        :weekdays,
        :starts_on,
        :next_due_on,
        :applicability,
        :campaign_id,
        :status,
        :version,
        :seed_key,
        :legacy_code,
        :created_by_id
      ])
      |> Map.merge(%{
        id: Ecto.UUID.generate(),
        inserted_at: timestamp,
        updated_at: timestamp,
        last_check: %{}
      })

    case Repo.insert_all(TaskTemplate, [attrs],
           on_conflict: :nothing,
           conflict_target: :seed_key,
           returning: true
         ) do
      {1, [inserted]} -> record_version!(inserted, actor_id)
      {0, _} -> :ok
    end
  end

  @doc "Called under the legacy profile lock; shares the template lock with generation."
  def legacy_instance(profile_id, code, period) do
    template =
      Repo.one(
        from t in TaskTemplate,
          where: t.seed_key == ^"legacy:#{profile_id}:#{code}",
          lock: "FOR UPDATE"
      )

    if template do
      Repo.one(
        from q in Quest,
          where:
            (q.template_id == ^template.id or
               (not q.managed and q.profile_id == ^profile_id and q.code == ^code)) and
              (q.status in ["waiting", "active"] or q.period_key == ^period or
                 (q.status == "completed" and
                    fragment(
                      "timezone('Europe/Prague', ? AT TIME ZONE 'UTC')::date >= timezone('Europe/Prague', now())::date",
                      q.completed_at
                    ))),
          order_by: [desc: q.inserted_at, desc: q.id],
          limit: 1
      )
    end
  end

  @doc "Explicit refresh or hourly job. Prague dates, no retroactive completions or XP."
  def generate(as_of \\ DateTime.utc_now()) do
    if Adventure.enabled?() do
      Repo.transaction(fn ->
        day = Stays.local_date(as_of)

        templates =
          Repo.all(
            from t in TaskTemplate,
              where: t.status == "active" and t.next_due_on <= ^day,
              order_by: t.id,
              lock: "FOR UPDATE SKIP LOCKED"
          )
          |> Repo.preload(:campaign)

        guest_state =
          if Enum.any?(templates, &(&1.applicability == "guests")), do: Guests.snapshot(day)

        Enum.map(templates, &generate_one(&1, day, as_of, guest_state))
      end)
    else
      {:error, :disabled}
    end
  end

  defp generate_one(template, day, as_of, guest_state) do
    due = Recurrence.latest(template, day)
    {eligible, state} = eligibility(template, day, due, guest_state)

    result =
      if (eligible and due) && Date.compare(due, template.next_due_on) != :lt do
        case open_tasks(template, true) do
          [task | _] -> roll_due!(task, template, due, as_of)
          [] -> maybe_create!(template, due, day, as_of)
        end
      else
        :skipped
      end

    next_due =
      if not eligible and due == day do
        template.next_due_on
      else
        if template.cadence == "once", do: nil, else: Recurrence.next(template, Date.add(day, 1))
      end

    template
    |> Changeset.change(
      next_due_on: next_due,
      last_check: %{
        "state" => state,
        "result" => Atom.to_string(result),
        "day" => Date.to_iso8601(day),
        "as_of" => DateTime.to_iso8601(as_of)
      }
    )
    |> persist!(:update)

    %{template_id: template.id, state: state, result: result}
  end

  defp eligibility(template, day, due, guests) do
    case template.applicability do
      "always" ->
        {true, "eligible"}

      "guests" ->
        {guests == "present" and due == day, guests || "unknown"}

      "campaign" ->
        campaign = template.campaign

        allowed =
          campaign && campaign.status == "active" &&
            Date.compare(day, campaign.starts_on) != :lt &&
            Date.compare(day, campaign.ends_on) != :gt &&
            due && Date.compare(due, campaign.starts_on) != :lt

        {allowed == true, if(allowed, do: "eligible", else: "outside_campaign")}
    end
  end

  defp maybe_create!(template, due, day, as_of) do
    period = Recurrence.period(template, due)
    legacy_recorded = legacy_recorded?(template, due)
    # Completion after a missed due date consumes that calendar day too.
    # A template edit/resume or a delayed job must not create another reward today.
    completed_query = from q in Quest, where: q.template_id == ^template.id

    completed_query =
      if template.legacy_code do
        from q in completed_query,
          or_where:
            not q.managed and q.profile_id == ^template.legacy_profile_id and
              q.code == ^template.legacy_code
      else
        completed_query
      end

    last_closed =
      Repo.one(
        from q in completed_query,
          where: q.status in ["completed", "cancelled"],
          select: type(max(coalesce(q.completed_at, q.archived_at)), :utc_datetime)
      )

    last_closed = if last_closed, do: Stays.local_date(last_closed)

    cond do
      legacy_recorded ->
        :already_recorded

      last_closed && (template.cadence == "once" or Date.compare(due, last_closed) != :gt) ->
        :already_closed

      Repo.exists?(
        from q in Quest, where: q.template_id == ^template.id and q.period_key == ^period
      ) ->
        :already_generated

      true ->
        first = if template.applicability == "guests", do: day, else: template.next_due_on

        first =
          if template.applicability == "campaign",
            do:
              Recurrence.next(template, Recurrence.max_date(first, template.campaign.starts_on)),
            else: first

        snapshot =
          definition(template)
          |> Map.merge(%{"template_id" => template.id, "template_version" => template.version})

        %Quest{
          managed: true,
          status: "waiting",
          scope: template.scope,
          assigned_profile_id: template.assigned_profile_id,
          created_by_id: template.created_by_id || template.legacy_profile_id,
          code: template.legacy_code || "template:" <> template.id,
          version: template.version,
          period_key: period,
          template_id: template.id,
          definition_snapshot: snapshot,
          category: template.category,
          priority: template.priority,
          description: template.description,
          first_due_on: first,
          due_on: due,
          schedule_history: history(first, due, as_of),
          evidence: %{
            "generated_at" => DateTime.to_iso8601(as_of),
            "source" => "recurring_template"
          }
        }
        |> Repo.insert!()

        :created
    end
  end

  defp roll_due!(task, template, due, as_of) do
    first = task.first_due_on || task.due_on || original_due(task, template.next_due_on)
    previous = task.due_on || first

    if Date.compare(due, previous) == :gt or is_nil(task.template_id) do
      shifts =
        Map.get(task.schedule_history, "shifts", []) ++
          if(Date.compare(due, previous) == :gt,
            do: [
              %{
                "from" => Date.to_iso8601(previous),
                "to" => Date.to_iso8601(due),
                "observed_at" => DateTime.to_iso8601(as_of)
              }
            ],
            else: []
          )

      task
      |> Changeset.change(
        template_id: template.id,
        first_due_on: first,
        due_on: due,
        schedule_history: %{"shifts" => shifts}
      )
      |> persist!(:update)
    end

    :rolled
  end

  defp original_due(%{period_key: "week:" <> date}, fallback) do
    case Date.from_iso8601(date) do
      {:ok, day} -> day
      _ -> fallback
    end
  end

  defp original_due(_task, fallback), do: fallback

  defp history(first, due, at) do
    if first == due,
      do: %{"shifts" => []},
      else: %{
        "shifts" => [
          %{
            "from" => Date.to_iso8601(first),
            "to" => Date.to_iso8601(due),
            "observed_at" => DateTime.to_iso8601(at)
          }
        ]
      }
  end

  defp open_tasks(template, lock?) do
    query =
      from q in Quest,
        where:
          q.template_id == ^template.id and q.status in ["waiting", "active"] and
            is_nil(q.archived_at),
        order_by: [desc: q.inserted_at, desc: q.id]

    query =
      if template.legacy_code do
        from q in query,
          or_where:
            not q.managed and q.profile_id == ^template.legacy_profile_id and
              q.code == ^template.legacy_code and q.status == "active"
      else
        query
      end

    query = if lock?, do: lock(query, "FOR UPDATE"), else: query
    Repo.all(query)
  end

  defp legacy_recorded?(%{legacy_code: nil}, _period), do: false

  defp legacy_recorded?(template, due) do
    legacy = Catalog.fetch(template.legacy_code)

    period =
      if legacy.cadence == "weekly",
        do: "week:" <> Date.to_iso8601(Date.beginning_of_week(due)),
        else: "once"

    Repo.exists?(
      from q in Quest,
        where:
          not q.managed and q.profile_id == ^template.legacy_profile_id and
            q.code == ^template.legacy_code and q.status in ["completed", "cancelled"] and
            q.period_key == ^period
    )
  end

  defp action(actor_id, fun) do
    if Adventure.enabled?() do
      Repo.transaction(fn ->
        with {:ok, id} <- Ecto.UUID.cast(actor_id),
             %Profile{} = actor <- Repo.get_by(Profile, id: id, active: true) do
          fun.(actor)
        else
          _ -> Repo.rollback(:invalid_profile)
        end
      end)
    else
      {:error, :disabled}
    end
  end

  defp validate_assignment!(template) do
    if template.assigned_profile_id &&
         not Repo.exists?(
           from p in Profile, where: p.id == ^template.assigned_profile_id and p.active
         ),
       do: Repo.rollback(:invalid_profile)
  end

  defp lock!(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %TaskTemplate{} = template <-
           Repo.one(from t in TaskTemplate, where: t.id == ^id, lock: "FOR UPDATE") do
      template
    else
      _ -> Repo.rollback(:not_found)
    end
  end

  defp record_version!(template, actor_id, extra \\ %{}) do
    Repo.insert!(%TemplateVersion{
      template_id: template.id,
      version: template.version,
      actor_id: actor_id,
      definition: Map.merge(definition(template), extra)
    })
  end

  def definition(template) do
    Map.new(
      [
        :title,
        :description,
        :category,
        :priority,
        :scope,
        :assigned_profile_id,
        :size,
        :xp,
        :cadence,
        :weekdays,
        :applicability,
        :campaign_id,
        :status,
        :version
      ],
      fn key -> {Atom.to_string(key), Map.get(template, key)} end
    )
    |> Map.put("starts_on", Date.to_iso8601(template.starts_on))
    |> Map.merge(%{"timezone" => "Europe/Prague", "rules_version" => "recurrence_v1"})
  end

  defp persist!(changeset, operation) do
    case apply(Repo, operation, [changeset]) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
