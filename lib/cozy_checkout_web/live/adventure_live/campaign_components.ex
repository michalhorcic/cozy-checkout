defmodule CozyCheckoutWeb.AdventureLive.CampaignComponents do
  use CozyCheckoutWeb, :html
  alias CozyCheckoutWeb.CurrencyHelper
  import CozyCheckoutWeb.AdventureLive.GameComponents

  attr :game, :map, required: true
  attr :definitions, :list, required: true
  attr :profile_selected, :boolean, required: true
  attr :settings, :boolean, required: true
  attr :campaign_form, :any, required: true
  attr :editing_id, :any, default: nil

  def campaigns(assigns) do
    visible =
      if assigns.settings,
        do: assigns.game.campaigns,
        else: Enum.take(Enum.filter(assigns.game.campaigns, &(&1.status == "active")), 1)

    assigns = assign(assigns, :visible_campaigns, visible)

    ~H"""
    <div id="adventure-shared" class="adventure-campaigns-column">
      <section class="adventure-panel adventure-season-panel">
        <header class="adventure-section-heading">
          <div>
            <p class="adventure-eyebrow">Táhneme za jeden provaz</p><h2>Kronika sezóny</h2>
          </div><span class="adventure-flag"><.symbol name="flag" /></span>
        </header>
        <div :if={@visible_campaigns == []} class="adventure-empty adventure-empty--season">
          <.symbol name="mountain-snow" /><h3>Nová sezóna na obzoru</h3><.link
            navigate={~p"/admin/adventure/settings"}
            class="adventure-text-link"
          >Připravit kampaň <.icon name="hero-arrow-right" class="size-4" /></.link>
        </div>
        <article
          :for={campaign <- @visible_campaigns}
          id={"campaign-#{campaign.id}"}
          class="adventure-campaign"
        >
          <header class="adventure-campaign-heading">
            <h3>{campaign.name}</h3><span class={"adventure-status adventure-status--#{campaign.status}"}>{status(
              campaign.status
            )}</span>
          </header>
          <p class="adventure-period">
            {period(campaign)} <span :if={@settings}>· {campaign.capacity} lůžek</span>
          </p>
          <.form
            :if={campaign.status == "draft" && @settings}
            for={%{}}
            as={:activation}
            id={"activate-campaign-#{campaign.id}"}
            phx-submit="activate-campaign"
            class="adventure-activation"
          >
            <input type="hidden" name="campaign_id" value={campaign.id} />
            <.input
              type="checkbox"
              name="activation[confirmed]"
              value={false}
              label="Potvrzuji období, cíle a stálou kapacitu. Aktivace uzamkne pravidla."
            />
            <div class="adventure-actions">
              <button class="adventure-button adventure-button--primary" disabled={!@profile_selected}>Aktivovat kampaň</button><button
                class="adventure-text-link"
                type="button"
                phx-click="edit-campaign"
                phx-value-id={campaign.id}
              >Upravit</button>
            </div>
          </.form>
          <div :if={campaign.status != "draft"} class="adventure-campaign-body">
            <.metrics
              :if={campaign.last_evaluation}
              snapshot={campaign.last_evaluation.snapshot}
              campaign={campaign}
            />
            <div :if={is_nil(campaign.last_evaluation)} class="adventure-pending">
              <.symbol name="compass" /><span>Zatím nepřepočítáno</span>
            </div>
            <div class="adventure-campaign-tools">
              <button
                id={"evaluate-campaign-#{campaign.id}"}
                class="adventure-button adventure-button--subtle"
                phx-click="evaluate-campaign"
                phx-value-id={campaign.id}
                disabled={!@profile_selected}
              ><.icon name="hero-arrow-path" class="size-4" /> Přepočítat</button><button
                :if={campaign.status == "active" && @settings}
                class="adventure-text-link"
                phx-click="close-campaign"
                phx-value-id={campaign.id}
                data-confirm="Uzavřít kampaň? Pravidla i hranice realizace zůstanou uzamčené."
                disabled={!@profile_selected}
              >Uzavřít</button>
            </div>
          </div>
          <h4 class="adventure-milestone-heading">Milníky na cestě</h4>
          <div class="adventure-medals">
            <div
              :for={definition <- @definitions}
              class={[
                "adventure-medal-card",
                "adventure-medal-card--#{unlock_state(campaign.unlocks, definition.code)}"
              ]}
            >
              <span class="adventure-medal"><.symbol name={
                if definition.code == "first_stay", do: "flag", else: "trophy"
              } /></span><strong>{if definition.code == "first_stay",
                do: "První stopa",
                else: "Chata v plném proudu"}</strong><span class="adventure-muted">{definition.required} {if definition.required ==
                                                                                                                1,
                                                                                                              do:
                                                                                                                "pobyt",
                                                                                                              else:
                                                                                                                "pobytů"}</span><span class="adventure-reward">+{definition.xp} XP</span><small>{unlock_status(
                campaign.unlocks,
                definition.code
              )}</small>
            </div>
          </div>
          <details :if={@settings} class="adventure-audit-details">
            <summary>Důkazy a zdrojová data</summary><p class="adventure-muted">
              Aktivace {campaign.activated_at} UTC · pravidla {campaign.rules_version} · Europe/Prague
            </p><.source_details
              :if={campaign.last_evaluation}
              snapshot={campaign.last_evaluation.snapshot}
            /><div :for={unlock <- campaign.unlocks}>
              <strong>{unlock.code} · {status(unlock.status)}</strong><p>
                Přiznáno {unlock.unlocked_at} UTC · {unlock.evidence["eligible_completed_stays"]} způsobilých pobytů · {unlock.xp} XP
              </p><p :if={unlock.revoked_at}>
                Odvoláno {unlock.revoked_at} UTC · {unlock.revocation_evidence[
                  "eligible_completed_stays"
                ]} způsobilých pobytů · odměna jednou kompenzována.
              </p>
            </div>
          </details>
        </article>
      </section>
      <section :if={@settings} class="adventure-panel adventure-campaign-editor">
        <header class="adventure-section-heading">
          <div>
            <p class="adventure-eyebrow">Naplánovat příští cestu</p><h2>
              {if @editing_id, do: "Upravit návrh", else: "Nová kampaň"}
            </h2>
          </div><.symbol name="compass" />
        </header>
        <.form
          for={@campaign_form}
          id="adventure-campaign-form"
          phx-submit="save-campaign"
          class="adventure-campaign-form"
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
            label="Cíl: budoucí lůžkonoci"
            min="1"
            required
          />
          <.input
            field={@campaign_form[:occupancy_goal]}
            type="number"
            label="Cíl: obsazenost (%)"
            min="1"
            max="100"
            required
          />
          <div class="adventure-actions">
            <button class="adventure-button adventure-button--primary" type="submit">Uložit návrh</button><button
              :if={@editing_id}
              class="adventure-text-link"
              type="button"
              phx-click="new-campaign"
            >Nový návrh</button>
          </div>
        </.form>
      </section>
      <details :if={@settings} class="adventure-journal">
        <summary>
          <span><.symbol name="notebook-pen" /> Přepočty kampaní · audit</span><.icon
            name="hero-chevron-down"
            class="size-4"
          />
        </summary><div class="adventure-journal-entries">
          <details
            :for={evaluation <- @game.evaluations}
            id={"evaluation-#{evaluation.id}"}
            class="adventure-audit-details"
          >
            <summary>{evaluation.campaign} · {evaluation.as_of} UTC · {evaluation.actor}</summary><.source_details snapshot={
              evaluation.snapshot
            } />
          </details>
        </div>
      </details>
      <details :if={@settings} class="adventure-journal">
        <summary>
          <span><.symbol name="sparkles" /> Společná XP · audit</span><.icon
            name="hero-chevron-down"
            class="size-4"
          />
        </summary><ul id="adventure-shared-ledger" class="adventure-audit-list">
          <li :for={entry <- @game.ledger}>
            <strong>{entry.amount} XP</strong><span>{entry.reason}</span><small>{entry.inserted_at} UTC · {entry.attribution}</small>
          </li>
        </ul>
      </details>
    </div>
    """
  end

  attr :snapshot, :map, required: true
  attr :campaign, :map, required: true

  defp metrics(assigns) do
    ~H"""
    <div class="adventure-metrics">
      <div class="adventure-metric">
        <span><.symbol name="house" /> Pobyty</span><strong>{CurrencyHelper.format_number(
          @snapshot["completed_stays"]
        )}<small> / {CurrencyHelper.format_number(@campaign.completed_goal)}</small></strong><progress
          aria-label="Cíl dokončených pobytů"
          value={CurrencyHelper.format_number(@snapshot["completed_stays"])}
          max={CurrencyHelper.format_number(@campaign.completed_goal)}
        ></progress>
      </div>
      <div class="adventure-metric">
        <span><.symbol name="flag" /> Budoucí lůžkonoci</span><strong>{CurrencyHelper.format_number(
          @snapshot["reserved_bednights"]
        )}<small> / {CurrencyHelper.format_number(@campaign.reserved_goal)}</small></strong><progress
          aria-label="Cíl budoucích lůžkonocí"
          value={CurrencyHelper.format_number(@snapshot["reserved_bednights"])}
          max={CurrencyHelper.format_number(@campaign.reserved_goal)}
        ></progress>
      </div>
      <div class="adventure-metric">
        <span><.symbol name="trees" /> Obsazenost</span><strong>{if @snapshot["occupancy_percent"],
          do:
            CurrencyHelper.format_number(@snapshot["occupancy_percent"],
              precision: 0,
              decimal_separator: ","
            ) <> " %",
          else: "—"}</strong><small>{if @snapshot["occupancy_percent"],
          do: "cíl #{@campaign.occupancy_goal} %",
          else: "zatím bez uzavřených nocí"}</small>
      </div>
      <div class="adventure-metric">
        <span><.symbol name="mountain-snow" /> Realizované noci</span><strong>{@snapshot[
          "realized_bednights"
        ]}</strong><small>lůžkonocí podle rezervací</small>
      </div>
    </div>
    <div class="adventure-data-status" role="status">
      <span class={
        if @snapshot["completeness"] == "complete",
          do: "adventure-data-dot",
          else: "adventure-data-dot adventure-data-dot--warning"
      }></span><span>Kvalita dat: {if @snapshot["completeness"] == "complete",
        do: "úplná",
        else: "neúplná"}</span><small>{checked_at(@snapshot["as_of"])}</small>
    </div>
    <p :if={@snapshot["completeness"] != "complete"} class="adventure-data-warning">
      Dílčí výsledky · XP se zatím nemění.
    </p>
    """
  end

  attr :snapshot, :map, required: true

  defp source_details(assigns) do
    ~H"""
    <dl class="adventure-source-data">
      <div>
        <dt>Zdroj a verze</dt><dd>{@snapshot["source"]} · {@snapshot["rules_version"]}</dd>
      </div><div>
        <dt>Přepočteno</dt><dd>{@snapshot["as_of"]}</dd>
      </div><div>
        <dt>Hranice realizace</dt><dd>{@snapshot["cutoff_on"]} · Europe/Prague</dd>
      </div><div>
        <dt>Dokončené / způsobilé pobyty</dt><dd>
          {CurrencyHelper.format_number(@snapshot["completed_stays"])} / {@snapshot[
            "eligible_completed_stays"
          ]}
        </dd>
      </div><div>
        <dt>Realizované / budoucí lůžkonoci</dt><dd>
          {CurrencyHelper.format_number(@snapshot["realized_bednights"])} / {CurrencyHelper.format_number(
            @snapshot["reserved_bednights"]
          )}
        </dd>
      </div><div>
        <dt>Úplnost / nejisté pobyty</dt><dd>
          {@snapshot["completeness"]} / {@snapshot["uncertain_stays"]}
        </dd>
      </div><div>
        <dt>Kapacita</dt><dd>{@snapshot["capacity"]} · ručně potvrzená konstanta</dd>
      </div>
    </dl><p class="adventure-muted">{@snapshot["definition"]}</p>
    """
  end

  defp period(campaign),
    do:
      Calendar.strftime(campaign.starts_on, "%d. %m.") <>
        " — " <> Calendar.strftime(campaign.ends_on, "%d. %m. %Y")

  defp checked_at(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _} -> Calendar.strftime(at, "%d. %m. · %H:%M UTC")
      _ -> value
    end
  end

  defp unlock_state(unlocks, code) do
    case Enum.find(unlocks, &(&1.code == code)) do
      nil -> "locked"
      unlock -> unlock.status
    end
  end

  defp unlock_status(unlocks, code), do: status(unlock_state(unlocks, code))
  defp status("draft"), do: "Návrh"
  defp status("active"), do: "Aktivní"
  defp status("closed"), do: "Uzavřená"
  defp status("unlocked"), do: "Získáno"
  defp status("revoked"), do: "Odvoláno"
  defp status("locked"), do: "Zamčeno"
end
