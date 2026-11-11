defmodule CozyCheckoutWeb.AdventureLive.Index do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Adventure
  alias CozyCheckout.Adventure.{Campaign, Campaigns}
  import CozyCheckoutWeb.AdventureLive.CampaignComponents

  @impl true
  def mount(_, _, socket) do
    if Adventure.enabled?() do
      {:ok,
       socket
       |> assign(page_title: "Cozy Adventure", selected_profile_id: nil, completing: nil)
       |> new_campaign()
       |> load()}
    else
      {:ok, redirect(socket, to: ~p"/admin")}
    end
  end

  @impl true
  def handle_event(event, params, socket) do
    if Adventure.enabled?() do
      handle_game_event(event, params, socket)
    else
      {:noreply, redirect(socket, to: ~p"/admin")}
    end
  end

  defp handle_game_event("initialize", _, socket) do
    result(socket, Adventure.initialize())
  end

  defp handle_game_event("save-campaign", %{"campaign" => attrs}, socket) do
    outcome =
      if id = socket.assigns.editing_campaign_id,
        do: Campaigns.update(id, attrs),
        else: Campaigns.create(attrs)

    case outcome do
      {:ok, _} ->
        result(new_campaign(socket), outcome)

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, campaign_form: to_form(changeset, as: :campaign))}

      error ->
        result(socket, error)
    end
  end

  defp handle_game_event("edit-campaign", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.game.campaigns, &(&1.id == id and &1.status == "draft")) do
      nil ->
        result(socket, {:error, :not_found})

      campaign ->
        {:noreply,
         assign(socket,
           editing_campaign_id: campaign.id,
           campaign_form: to_form(Campaign.changeset(campaign, %{}), as: :campaign)
         )}
    end
  end

  defp handle_game_event("new-campaign", _, socket), do: {:noreply, new_campaign(socket)}

  defp handle_game_event("activate-campaign", %{"campaign_id" => id} = params, socket) do
    confirmed = get_in(params, ["activation", "confirmed"]) == "true"
    result(socket, Campaigns.activate(id, socket.assigns.selected_profile_id, confirmed))
  end

  defp handle_game_event("evaluate-campaign", %{"id" => id}, socket) do
    result(socket, Campaigns.evaluate(id, socket.assigns.selected_profile_id))
  end

  defp handle_game_event("close-campaign", %{"id" => id}, socket) do
    result(socket, Campaigns.close(id, socket.assigns.selected_profile_id))
  end

  defp handle_game_event("profile", %{"profile" => %{"id" => id}}, socket) do
    {:noreply, socket |> assign(selected_profile_id: id, completing: nil) |> load()}
  end

  defp handle_game_event("activate", %{"code" => code}, socket) do
    result(socket, Adventure.activate_quest(socket.assigns.selected_profile_id, code))
  end

  defp handle_game_event("prepare-completion", %{"id" => id}, socket) do
    quest = Enum.find(socket.assigns.data.quests, &(&1.id == id and &1.status == "active"))
    {:noreply, assign(socket, completing: quest)}
  end

  defp handle_game_event("cancel-completion", _, socket),
    do: {:noreply, assign(socket, completing: nil)}

  defp handle_game_event("complete", %{"completion" => %{"note" => note}}, socket) do
    if quest = socket.assigns.completing do
      result(
        socket,
        Adventure.complete_manual_quest(socket.assigns.selected_profile_id, quest.id, note)
      )
    else
      {:noreply, socket}
    end
  end

  defp handle_game_event(_, _, socket), do: {:noreply, socket}

  defp result(socket, {:ok, _}) do
    {:noreply,
     socket |> assign(completing: nil) |> load() |> put_flash(:info, "Herní postup uložen.")}
  end

  defp result(socket, {:error, reason}) do
    message =
      case reason do
        :active_limit -> "Můžeš mít nejvýše 3 aktivní osobní questy."
        :evidence_required -> "Přidej poznámku o splnění (10–1000 znaků)."
        :invalid_profile -> "Nejprve vyber herní profil."
        :confirmation_required -> "Před aktivací potvrď období, cíle a kapacitu."
        :past_campaign -> "Nelze aktivovat již skončené období."
        :immutable_campaign -> "Po aktivaci nelze období a pravidla měnit."
        :inactive_campaign -> "Nejprve aktivuj kampaň."
        %Ecto.Changeset{} -> "Kampaň nelze aktivovat. Může být aktivní nejvýše jedna kampaň."
        _ -> "Akci nelze dokončit. Obnov stránku a zkontroluj výběr profilu."
      end

    {:noreply, put_flash(socket, :error, message)}
  end

  defp load(socket) do
    {:ok, data} = Adventure.dashboard(socket.assigns.selected_profile_id)
    {:ok, game} = Campaigns.overview()

    assign(socket,
      data: data,
      game: game,
      catalog: Adventure.catalog(),
      profile_form: to_form(%{"id" => data.profile && data.profile.id}, as: :profile),
      completion_form: to_form(%{"note" => ""}, as: :completion)
    )
  end

  defp new_campaign(socket) do
    campaign = %Campaign{
      name: "Zimní kampaň 2026/27",
      starts_on: ~D[2026-12-01],
      ends_on: ~D[2027-03-31],
      capacity: 45,
      completed_goal: 10,
      reserved_goal: 1000,
      occupancy_goal: 50
    }

    assign(socket,
      editing_campaign_id: nil,
      campaign_form: to_form(Campaign.changeset(campaign, %{}), as: :campaign)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      content_class="mx-auto w-full max-w-5xl space-y-6"
      main_class="px-4 py-6 sm:px-6 lg:px-8"
    >
      <header class="space-y-2">
        <p class="text-sm uppercase tracking-wide">Jindřichův dům · hobby hra</p>
        <h1 class="text-3xl font-bold">Cozy Adventure</h1>
        <p>
          Malé kroky pro chatu, vlastní dobrodružství. Herní XP nejsou peníze ani provozní ukazatel.
        </p>
      </header>
      <nav aria-label="Adventure" class="flex flex-wrap gap-2">
        <.link navigate={~p"/admin/adventure"} class="btn btn-sm">Přehled</.link>
        <.link navigate={~p"/admin/adventure/quests"} class="btn btn-sm">Questy</.link>
        <.link navigate={~p"/admin/adventure/settings"} class="btn btn-sm">Nastavení a audit</.link>
      </nav>
      <p class="alert" role="note">
        Výběr profilu je vlastní prohlášení, nikoli ověřená identita. Platí jen na této stránce do jejího opuštění. Veškeré akce chrání společný admin PIN.
      </p>
      <section :if={@data.profiles == []} class="rounded-xl border border-base-300 p-5 space-y-3">
        <h2 class="text-xl font-semibold">Začít dobrodružství</h2>
        <p>Založit herní profily Michal a Lucka. Provozní záznamy chaty se tím nemění.</p>
        <button id="adventure-initialize" phx-click="initialize" class="btn btn-primary">Založit herní profily</button>
      </section>
      <.form
        :if={@data.profiles != []}
        for={@profile_form}
        id="adventure-profile"
        phx-change="profile"
      >
        <.input
          field={@profile_form[:id]}
          type="select"
          label="Aktivní herní profil"
          prompt="Vyber svůj profil"
          options={Enum.map(@data.profiles, &{&1.display_name, &1.id})}
        />
      </.form>
      <section
        :if={@data.profile}
        id="adventure-progress"
        class="rounded-xl border border-base-300 p-5"
      >
        <h2 class="text-xl font-semibold">{@data.profile.display_name} · úroveň {@data.level}</h2>
        <p>
          {@data.total_xp} XP · další úroveň při {div(100 * @data.level * (@data.level + 1), 2)} XP
        </p>
      </section>
      <section :if={@data.profile} class="space-y-4">
        <h2 class="text-xl font-semibold">Aktivní osobní questy · nejvýše 3</h2>
        <p :if={!Enum.any?(@data.quests, &(&1.status == "active"))}>Vyber quest z katalogu níže.</p>
        <article
          :for={quest <- Enum.filter(@data.quests, &(&1.status == "active"))}
          id={"adventure-quest-#{quest.id}"}
          class="rounded-xl border border-base-300 p-5 space-y-2"
        >
          <h3 class="font-semibold">
            {quest.definition_snapshot["title"]} · {quest.definition_snapshot["xp"]} XP
          </h3>
          <p class="text-sm">Aktivní · období {quest.period_key}</p>
          <button
            phx-click="prepare-completion"
            phx-value-id={quest.id}
            class="btn btn-primary btn-sm"
          >Potvrdit splnění</button>
        </article>
      </section>
      <section :if={@completing} class="rounded-xl border border-primary p-5 space-y-3">
        <h2 class="text-xl font-semibold">Potvrzení: {@completing.definition_snapshot["title"]}</h2>
        <p>
          Potvrzuji za profil {@data.profile.display_name}, že úkol je hotový. Do poznámky neuváděj osobní údaje hostů.
        </p>
        <.form
          for={@completion_form}
          id="adventure-completion"
          phx-submit="complete"
          class="space-y-3"
        >
          <.input
            field={@completion_form[:note]}
            type="textarea"
            label="Co se podařilo dokončit?"
            minlength="10"
            maxlength="1000"
            required
          />
          <button class="btn btn-primary" type="submit">Úkol je splněný</button>
          <button class="btn btn-ghost" type="button" phx-click="cancel-completion">Zpět</button>
        </.form>
      </section>
      <section :if={@data.profile} class="space-y-3">
        <h2 class="text-xl font-semibold">Katalog questů</h2>
        <p>
          Týdenní šablony lze aktivovat jednou za kalendářní týden v Europe/Prague. Aktivní quest lze dokončit i později; odměna zůstává v jeho původním období.
        </p>
        <div class="grid gap-3 sm:grid-cols-2">
          <article :for={quest <- @catalog} class="rounded-xl border border-base-300 p-5 space-y-3">
            <h3 class="font-semibold">{quest.title}</h3>
            <p>{quest.xp} XP · {if quest.cadence == "weekly", do: "Týdenní", else: "Jednorázový"}</p>
            <button
              id={"activate-#{quest.code}"}
              phx-click="activate"
              phx-value-code={quest.code}
              class="btn btn-outline btn-sm"
            >Aktivovat quest</button>
          </article>
        </div>
      </section>
      <section :if={@data.profile} class="space-y-3">
        <h2 class="text-xl font-semibold">Historie splnění · posledních 100 questů</h2>
        <article
          :for={quest <- Enum.filter(@data.quests, &(&1.status == "completed"))}
          class="rounded-xl border border-base-300 p-4"
        >
          <h3 class="font-semibold">{quest.definition_snapshot["title"]} · Splněno</h3>
          <p>{quest.completed_at} UTC · {quest.evidence["attribution"]}</p>
          <p class="whitespace-pre-wrap">{quest.evidence["note"]}</p>
        </article>
      </section>
      <section :if={@live_action == :settings} class="rounded-xl border border-base-300 p-5 space-y-3">
        <h2 class="text-xl font-semibold">Nastavení a audit</h2>
        <p>
          Modul je zapnutý konfigurací ADVENTURE_ENABLED=true. Vypnutí zachová herní historii a zablokuje další herní akce. Pobytová data se čtou pouze při ručním přepočtu.
        </p>
        <p>
          Pravidla šablon: verze 1. Zápisy probíhají pouze do adventure_* tabulek. Opravy XP se ukládají samostatným kompenzačním záznamem.
        </p>
        <h3 class="font-semibold">Posledních 20 XP transakcí vybraného profilu</h3>
        <ul id="adventure-ledger" class="space-y-2">
          <li :for={entry <- @data.ledger}>
            {entry.amount} XP · {entry.reason} · {entry.inserted_at} UTC · {entry.attribution}
          </li>
        </ul>
      </section>
      <.campaigns
        game={@game}
        definitions={Campaigns.achievements()}
        profile_selected={!is_nil(@data.profile)}
        settings={@live_action == :settings}
        campaign_form={@campaign_form}
        editing_id={@editing_campaign_id}
      />
      <section class="rounded-xl border border-base-300 p-5 space-y-3">
        <h2 class="text-xl font-semibold">Další rozvoj chaty</h2>
        <p>Obchod · Finance · Kuchyně · Provoz · Hosté: dosud nevyhodnoceno.</p>
        <p>Rekonstrukce: neaktivní roadmapa, bez vykazování úspor či investičního fondu.</p>
      </section>
    </Layouts.app>
    """
  end
end
