defmodule CozyCheckoutWeb.AdventureLive.CampaignComponents do
  use CozyCheckoutWeb, :html

  attr :game, :map, required: true
  attr :definitions, :list, required: true
  attr :profile_selected, :boolean, required: true
  attr :settings, :boolean, required: true
  attr :campaign_form, :any, required: true
  attr :editing_id, :any, default: nil

  def campaigns(assigns) do
    ~H"""
    <section id="adventure-shared" class="space-y-4">
      <header class="rounded-xl border border-base-300 p-5">
        <h2 class="text-2xl font-semibold">Společná chata · úroveň {@game.level}</h2>
        <p>{@game.total_xp} společných XP. Automatické milníky neodměňují osobní profily.</p>
      </header>
      <p :if={@game.campaigns == []}>
        Zatím není založená kampaň. Návrh vytvoříš v Nastavení a auditu.
      </p>
      <details
        :for={campaign <- @game.campaigns}
        id={"campaign-#{campaign.id}"}
        open={campaign.status == "active"}
        class="rounded-xl border border-base-300 p-5 space-y-3"
      >
        <summary class="cursor-pointer font-semibold">
          {campaign.name} · {status(campaign.status)}
        </summary>
        <p>
          {campaign.starts_on} – {campaign.ends_on} · Europe/Prague · kapacita {campaign.capacity} lůžek
        </p>
        <p>
          Cíle: {campaign.completed_goal} dokončených pobytů, {campaign.reserved_goal} budoucích rezervovaných lůžkonocí, {campaign.occupancy_goal} % obsazenosti uzavřených nocí.
        </p>
        <p :if={campaign.status == "draft"}>
          Návrh není aktivní. Před aktivací potvrď období, cíle a stálou kapacitu pro celé období.
        </p>
        <.form
          :if={campaign.status == "draft"}
          for={%{}}
          as={:activation}
          id={"activate-campaign-#{campaign.id}"}
          phx-submit="activate-campaign"
          class="space-y-3"
        >
          <input type="hidden" name="campaign_id" value={campaign.id} />
          <.input
            type="checkbox"
            name="activation[confirmed]"
            value={false}
            label="Potvrzuji období, cíle a kapacitu; po aktivaci budou pravidla uzamčená."
          />
          <button class="btn btn-primary btn-sm" disabled={!@profile_selected}>Aktivovat kampaň</button>
          <button
            :if={@settings}
            class="btn btn-ghost btn-sm"
            type="button"
            phx-click="edit-campaign"
            phx-value-id={campaign.id}
          >Upravit návrh</button>
        </.form>
        <div :if={campaign.status != "draft"} class="space-y-3">
          <p>
            Aktivace: {campaign.activated_at} UTC. Milníky počítají až odjezdy od následujícího dne v Praze.
          </p>
          <button
            id={"evaluate-campaign-#{campaign.id}"}
            class="btn btn-outline btn-sm"
            phx-click="evaluate-campaign"
            phx-value-id={campaign.id}
            disabled={!@profile_selected}
          >Přepočítat z provozních dat</button>
          <button
            :if={campaign.status == "active"}
            class="btn btn-ghost btn-sm"
            phx-click="close-campaign"
            phx-value-id={campaign.id}
            data-confirm="Uzavřít kampaň? Období a pravidla zůstanou uzamčené, půjde už jen přepočítávat opravy."
            disabled={!@profile_selected}
          >Uzavřít kampaň</button>
          <p :if={is_nil(campaign.last_evaluation)}>Zatím nepřepočítáno. Metriky nejsou dostupné.</p>
          <.metrics :if={campaign.last_evaluation} snapshot={campaign.last_evaluation.snapshot} />
          <div :if={campaign.last_evaluation} class="space-y-2">
            <label class="block" for={"completed-goal-#{campaign.id}"}>Cíl dokončených pobytů</label>
            <progress
              id={"completed-goal-#{campaign.id}"}
              class="progress progress-primary"
              value={campaign.last_evaluation.snapshot["completed_stays"]}
              max={campaign.completed_goal}
            />
            <label class="block" for={"reserved-goal-#{campaign.id}"}>Cíl budoucích rezervovaných lůžkonocí</label>
            <progress
              id={"reserved-goal-#{campaign.id}"}
              class="progress progress-primary"
              value={campaign.last_evaluation.snapshot["reserved_bednights"]}
              max={campaign.reserved_goal}
            />
          </div>
        </div>
        <h3 class="font-semibold">Automatické achievementy</h3>
        <ul class="space-y-2">
          <li :for={definition <- @definitions}>
            {definition.title} · {definition.xp} společných XP · {unlock_status(
              campaign.unlocks,
              definition.code
            )}
          </li>
        </ul>
        <details :for={unlock <- campaign.unlocks} class="text-sm">
          <summary>Důkaz: {unlock.code} · {status(unlock.status)}</summary>
          <p>
            Přiznáno {unlock.unlocked_at} UTC · pravidla {unlock.rules_version} · {unlock.evidence[
              "eligible_completed_stays"
            ]} způsobilých pobytů · zdroj {unlock.evidence["source"]} · přepočet {unlock.evidence[
              "as_of"
            ]}
          </p>
          <p :if={unlock.revoked_at}>
            Odvoláno {unlock.revoked_at} UTC · po opravě {unlock.revocation_evidence[
              "eligible_completed_stays"
            ]} způsobilých pobytů. XP kompenzována jednou; tento milník se v kampani znovu neodměňuje.
          </p>
        </details>
      </details>
      <p :if={!@profile_selected}>
        Pro aktivaci, přepočet či uzavření nejprve vyber profil kvůli auditu ruční akce.
      </p>
      <section :if={@settings} class="rounded-xl border border-base-300 p-5 space-y-3">
        <h2 class="text-xl font-semibold">
          {if @editing_id, do: "Upravit návrh kampaně", else: "Nový návrh kampaně"}
        </h2>
        <p>
          Kapacita je ručně potvrzená stálá hodnota pro celé období. Historii blokací ani změn kapacity provozní systém neuchovává. Zvolenou hodnotu před aktivací ověř.
        </p>
        <.form
          for={@campaign_form}
          id="adventure-campaign-form"
          phx-submit="save-campaign"
          class="grid gap-3 sm:grid-cols-2"
        >
          <.input field={@campaign_form[:name]} label="Název" required maxlength="100" />
          <.input
            field={@campaign_form[:capacity]}
            type="number"
            label="Stálá kapacita (lůžka)"
            min="1"
            max="500"
            required
          />
          <.input field={@campaign_form[:starts_on]} type="date" label="Začátek včetně" required />
          <.input field={@campaign_form[:ends_on]} type="date" label="Konec včetně" required />
          <.input
            field={@campaign_form[:completed_goal]}
            type="number"
            label="Cíl: dokončené pobyty"
            min="1"
            required
          />
          <.input
            field={@campaign_form[:reserved_goal]}
            type="number"
            label="Cíl: budoucí rezervované lůžkonoci"
            min="1"
            required
          />
          <.input
            field={@campaign_form[:occupancy_goal]}
            type="number"
            label="Cíl: obsazenost uzavřených nocí (%)"
            min="1"
            max="100"
            required
          />
          <div class="flex gap-2 items-end">
            <button class="btn btn-primary" type="submit">Uložit návrh</button>
            <button :if={@editing_id} class="btn btn-ghost" type="button" phx-click="new-campaign">Nový návrh</button>
          </div>
        </.form>
      </section>
      <section :if={@settings} class="rounded-xl border border-base-300 p-5 space-y-3">
        <h3 class="font-semibold">Posledních 20 přepočtů kampaní</h3>
        <details :for={evaluation <- @game.evaluations} id={"evaluation-#{evaluation.id}"}>
          <summary>
            {evaluation.campaign} · {evaluation.as_of} UTC · profil {evaluation.actor} (vlastní výběr)
          </summary>
          <.metrics snapshot={evaluation.snapshot} />
        </details>
      </section>
      <section :if={@settings} class="rounded-xl border border-base-300 p-5 space-y-3">
        <h3 class="font-semibold">Posledních 20 společných XP transakcí</h3>
        <ul id="adventure-shared-ledger" class="space-y-2">
          <li :for={entry <- @game.ledger}>
            {entry.amount} XP · {entry.reason} · {entry.inserted_at} UTC · automatická odměna / oprava
          </li>
        </ul>
      </section>
    </section>
    """
  end

  attr :snapshot, :map, required: true

  defp metrics(assigns) do
    ~H"""
    <div class="space-y-3">
      <p role="status">
        Kvalita dat: {if @snapshot["completeness"] == "complete",
          do: "Úplné pro definovaná pravidla",
          else: "Neúplné / nekonzistentní"} · nejisté pobyty: {@snapshot["uncertain_stays"]}
      </p>
      <p class="text-sm">
        Zdroj: rezervace · přepočteno {@snapshot["as_of"]} · hranice realizace {@snapshot["cutoff_on"]} (Europe/Prague) · pravidla {@snapshot[
          "rules_version"
        ]}
      </p>
      <dl class="grid gap-3 sm:grid-cols-2">
        <div>
          <dt>Dokončené pobyty / pro milníky</dt><dd>
            {@snapshot["completed_stays"]} / {@snapshot["eligible_completed_stays"]}
          </dd>
        </div>
        <div>
          <dt>Realizované lůžkonoci podle stavů rezervací</dt><dd>
            {@snapshot["realized_bednights"]}
          </dd>
        </div>
        <div>
          <dt>Budoucí rezervované lůžkonoci</dt><dd>{@snapshot["reserved_bednights"]}</dd>
        </div>
        <div>
          <dt>Obsazenost uzavřených nocí</dt><dd>
            {if @snapshot["occupancy_percent"],
              do: @snapshot["occupancy_percent"] <> " %",
              else: "Nedostupná – žádné uzavřené noci"}
          </dd>
        </div>
      </dl>
      <p :if={@snapshot["completeness"] != "complete"} class="alert alert-warning">
        Dílčí hodnoty nejsou úplným výsledkem. Z těchto podkladů se XP nepřiznávají ani neodebírají.
      </p>
      <details class="text-sm">
        <summary>Definice a omezení</summary><p>{@snapshot["definition"]}</p><p>
          Kapacita: {@snapshot["capacity"]}, ručně potvrzená konstanta. Stavy rezervací nejsou nezávislým potvrzením skutečné účasti hostů. Přepočet čte současná data; nepředstírá historický snapshot provozu.
        </p>
      </details>
    </div>
    """
  end

  defp unlock_status(unlocks, code) do
    case Enum.find(unlocks, &(&1.code == code)) do
      nil -> "Zamčeno"
      unlock -> status(unlock.status)
    end
  end

  defp status("draft"), do: "Návrh"
  defp status("active"), do: "Aktivní"
  defp status("closed"), do: "Uzavřená"
  defp status("unlocked"), do: "Získáno"
  defp status("revoked"), do: "Odvoláno a kompenzováno"
end
