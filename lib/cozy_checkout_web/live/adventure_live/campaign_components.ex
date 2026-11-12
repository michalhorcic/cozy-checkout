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
  attr :selected_id, :any, default: nil
  attr :search, :string, default: ""

  def campaigns(assigns) do
    readable = Enum.reject(assigns.game.campaigns, &(&1.status == "draft"))

    selected =
      Enum.find(readable, &(&1.id == assigns.selected_id)) ||
        Enum.find(readable, &(&1.status == "active")) || List.first(readable)

    visible = if assigns.settings, do: assigns.game.campaigns, else: List.wrap(selected)

    assigns =
      assigns
      |> assign(:visible_campaigns, visible)
      |> assign(:today, CozyCheckout.Adventure.Sources.Stays.today())
      |> assign(
        :season_options,
        Enum.filter(
          readable,
          &String.contains?(String.downcase(&1.name), String.downcase(assigns.search))
        )
      )
      |> assign(:season_count, length(readable))

    ~H"""
    <div id="adventure-shared" class="adventure-campaigns-column">
      <section class="adventure-panel adventure-season-panel">
        <header class="adventure-section-heading">
          <div>
            <p class="adventure-eyebrow">Táhneme za jeden provaz</p><h2>Kronika sezóny</h2>
          </div><span class="adventure-flag"><.symbol name="flag" /></span>
        </header>
        <details
          :if={!@settings && @season_count > 1}
          id="adventure-season-picker"
          class="adventure-audit-details"
        >
          <summary>Otevřít jinou sezónu</summary>
          <.form
            for={%{"search" => @search}}
            as={:season}
            phx-change="search-campaigns"
            id="adventure-season-search"
          >
            <.input
              name="season[search]"
              value={@search}
              type="search"
              label="Hledat sezónu"
              phx-debounce="200"
            />
          </.form>
          <div class="adventure-actions flex-wrap">
            <button
              :for={season <- @season_options}
              type="button"
              class="adventure-button adventure-button--subtle"
              phx-click="select-campaign"
              phx-value-id={season.id}
              aria-pressed={Enum.any?(@visible_campaigns, &(&1.id == season.id))}
            >
              {season.name} · {status(season.status)}
            </button>
          </div>
          <p :if={@season_options == []} class="adventure-muted">Žádná sezóna neodpovídá hledání.</p>
        </details>
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
            {period(campaign)}
            <span :if={@settings && campaign.capacity}>· {campaign.capacity} lůžek</span>
            <span :if={campaign.rules_version == "season_v1"}> · kronika bez automatických XP</span>
            <span :if={campaign.last_evaluation && campaign.last_evaluation.version}> · verze {campaign.last_evaluation.version}</span>
          </p>
          <.form
            :if={campaign.status == "draft" && @settings}
            for={%{}}
            as={:activation}
            id={"activate-campaign-#{campaign.id}"}
            phx-submit={
              if historical_draft?(campaign, @today),
                do: "archive-historical",
                else: "activate-campaign"
            }
            class="adventure-activation"
          >
            <input type="hidden" name="campaign_id" value={campaign.id} />
            <.input
              type="checkbox"
              name="activation[confirmed]"
              value={false}
              label={
                if historical_draft?(campaign, @today),
                  do:
                    "Potvrzuji historické období. Zápis vytvoří uzavřenou kroniku bez XP a bez spuštění questů.",
                  else:
                    "Potvrzuji období a pravidla. Aktivace je uzamkne; kapacita je volitelná pro novou kroniku."
              }
            />
            <div class="adventure-actions">
              <button class="adventure-button adventure-button--primary" disabled={!@profile_selected}>
                {if historical_draft?(campaign, @today),
                  do: "Zapsat historickou sezónu",
                  else: "Aktivovat kampaň"}
              </button>
              <button
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
                :if={campaign.rules_version != "season_v1" || campaign.status == "active"}
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
              <.link
                :if={
                  !@settings && campaign.rules_version == "season_v1" && campaign.status == "closed"
                }
                navigate={~p"/admin/adventure/settings"}
                class="adventure-text-link"
              >Verze a opravy v Nastavení</.link>
            </div>
            <.form
              :if={@settings && campaign.rules_version == "season_v1" && campaign.status == "closed"}
              for={%{}}
              as={:correction}
              id={"correct-campaign-#{campaign.id}"}
              phx-submit="correct-campaign"
              class="adventure-activation"
            >
              <input type="hidden" name="campaign_id" value={campaign.id} />
              <.input
                name="correction[reason]"
                value=""
                type="textarea"
                label="Důvod nové verze kroniky"
                required
                maxlength="1000"
              />
              <p class="adventure-muted">
                Nový přepočet uchová původní výsledek. Úhrady budou aktuální k přepočtu; období zůstává stejné.
              </p>
              <button
                type="submit"
                class="adventure-button adventure-button--subtle"
                disabled={!@profile_selected}
              >Uložit novou verzi</button>
            </.form>
          </div>
          <h4 :if={campaign.rules_version == "stays_v1"} class="adventure-milestone-heading">
            Milníky na cestě
          </h4>
          <div :if={campaign.rules_version == "stays_v1"} class="adventure-medals">
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
              {if @editing_id, do: "Upravit návrh", else: "Nová sezónní kronika"}
            </h2>
          </div><.symbol name="compass" />
        </header>
        <.form
          for={@campaign_form}
          id="adventure-campaign-form"
          phx-submit="save-campaign"
          class="adventure-campaign-form"
        >
          <input
            type="hidden"
            name="campaign[rules_version]"
            value={@campaign_form[:rules_version].value}
          />
          <p class="adventure-muted">
            Nová kronika sleduje skutečný provoz bez automatických odměn. Cíle nejsou povinné. Minulé období lze po uložení zapsat přímo jako uzavřenou historickou sezónu.
          </p>
          <.input field={@campaign_form[:name]} label="Název" required maxlength="100" />
          <.input
            field={@campaign_form[:capacity]}
            type="number"
            label="Stálá kapacita (lůžka, bez ní nebude procentní obsazenost)"
            min="1"
            max="500"
            required={@campaign_form[:rules_version].value == "stays_v1"}
          />
          <.input field={@campaign_form[:starts_on]} type="date" label="Začátek včetně" required />
          <.input field={@campaign_form[:ends_on]} type="date" label="Konec včetně" required />
          <.input
            field={@campaign_form[:completed_goal]}
            type="number"
            label="Cíl: dokončené pobyty"
            min="1"
            required={@campaign_form[:rules_version].value == "stays_v1"}
          />
          <.input
            field={@campaign_form[:reserved_goal]}
            type="number"
            label="Cíl: budoucí lůžkonoci"
            min="1"
            required={@campaign_form[:rules_version].value == "stays_v1"}
          />
          <.input
            field={@campaign_form[:occupancy_goal]}
            type="number"
            label="Cíl: obsazenost (%)"
            min="1"
            max="100"
            required={@campaign_form[:rules_version].value == "stays_v1"}
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
            <summary>
              {evaluation.campaign} · {if evaluation.version,
                do: "verze #{evaluation.version}",
                else: "původní přepočet"} · {evaluation.as_of} UTC · {evaluation.actor}
            </summary>
            <p :if={evaluation.correction_reason} class="adventure-muted">
              Důvod: {evaluation.correction_reason}
            </p>
            <.chronicle_metrics
              :if={evaluation.snapshot["rules_version"] == "season_v1"}
              snapshot={evaluation.snapshot}
            />
            <.source_details snapshot={evaluation.snapshot} />
          </details>
        </div>
      </details>
      <p :if={@settings && length(@game.campaigns) == 50} class="adventure-muted">
        Zobrazeno posledních 50 sezón.
      </p>
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

  defp metrics(%{snapshot: %{"rules_version" => "season_v1"}} = assigns) do
    ~H"""
    <.chronicle_metrics snapshot={@snapshot} />
    <p
      :if={@campaign.completed_goal || @campaign.reserved_goal || @campaign.occupancy_goal}
      class="adventure-muted"
    >
      Volitelné cíle:
      <span :if={@campaign.completed_goal}>{@campaign.completed_goal} dokončených pobytů. </span>
      <span :if={@campaign.reserved_goal}>{@campaign.reserved_goal} budoucích lůžkonocí. </span>
      <span :if={@campaign.occupancy_goal}>{@campaign.occupancy_goal} % obsazenosti.</span>
      Bez automatické odměny.
    </p>
    """
  end

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

  defp chronicle_metrics(assigns) do
    ~H"""
    <div class="adventure-metrics" data-season-metrics>
      <.chronicle_card
        snapshot={@snapshot}
        source="stays"
        metric="realized_bednights"
        label="Realizované lůžkonoci"
        symbol="mountain-snow"
        note="Osoby × uskutečněné noci v období"
      />
      <.chronicle_card
        snapshot={@snapshot}
        source="stays"
        metric="completed_stays"
        label="Dokončené pobyty"
        symbol="house"
        note="Odjezd v období sezóny"
      />
      <.chronicle_card
        snapshot={@snapshot}
        source="stays"
        metric="occupancy_percent"
        label="Obsazenost"
        symbol="trees"
        kind="percent"
        note="Bez kapacity nebo uzavřených nocí není dostupná"
      />
      <.chronicle_card
        snapshot={@snapshot}
        source="bar"
        metric="received_amount"
        label="Inkaso baru bez servisu"
        symbol="coins"
        kind="money"
        note="Platné evidované platby, ne prodeje"
      />
      <.chronicle_card
        snapshot={@snapshot}
        source="billing"
        metric="period_net_amount"
        label="Inkaso ubytování po vratkách"
        symbol="coins"
        kind="money"
        note="Platby minus refundace v období"
      />
      <.chronicle_card
        snapshot={@snapshot}
        source="billing"
        metric="settlement_billed_amount"
        label="Vyúčtování pobytů sezóny"
        symbol="notebook-pen"
        kind="money"
        note="Vydané konečné doklady včetně oprav"
      />
    </div>
    <div class="adventure-data-status" role="status">
      <span>Kvalita dat: u každé metriky zvlášť</span><small>{checked_at(@snapshot["as_of"])}</small>
    </div>
    <details class="adventure-audit-details" data-season-finances>
      <summary>Otevřít účetní list kroniky</summary>
      <p class="adventure-muted">
        Inkaso v období a vyúčtování pobytů jsou dva různé pohledy. Nesčítají se a nejsou ziskem. Zdrojem jsou evidované záznamy, nikoli úplný bankovní audit.
      </p>
      <h4>Inkaso v období</h4>
      <dl class="adventure-source-data">
        <div>
          <dt>Bar · servisní účty zvlášť</dt><dd>
            {money(metric_value(@snapshot, "bar", "service_received_amount"))}
          </dd>
        </div>
        <div>
          <dt>Bar · hotovost bez servisu</dt><dd>
            {money(metric_value(@snapshot, "bar", "cash_received_amount"))}
          </dd>
        </div>
        <div>
          <dt>Bar · QR bez servisu</dt><dd>
            {money(metric_value(@snapshot, "bar", "qr_received_amount"))}
          </dd>
        </div>
        <div>
          <dt>Ubytování · přijaté platby</dt><dd>
            {money(metric_value(@snapshot, "billing", "period_receipts_amount"))}
          </dd>
        </div>
        <div>
          <dt>Ubytování · refundace</dt><dd>
            {money(metric_value(@snapshot, "billing", "period_refunds_amount"))}
          </dd>
        </div>
      </dl>
      <p class="adventure-muted">
        Barové platby mohou obsahovat spropitné. U částečných plateb nelze spolehlivě oddělit prodej a spropitné. Servis se rozlišuje podle aktuálního označení účtu; smazaná platba není doložená refundace.
      </p>
      <h4>Pobyty s odjezdem v sezóně</h4>
      <dl class="adventure-source-data">
        <div>
          <dt>Celkově evidováno na úhradách</dt><dd>
            {money(metric_value(@snapshot, "billing", "settlement_paid_amount"))}
          </dd>
        </div>
        <div>
          <dt>Zbývá u vyúčtovaných plátců</dt><dd>
            {money(metric_value(@snapshot, "billing", "settlement_remaining_amount"))}
          </dd>
        </div>
        <div>
          <dt>Přeplatky vyúčtovaných plátců</dt><dd>
            {money(metric_value(@snapshot, "billing", "settlement_overpayment_amount"))}
          </dd>
        </div>
        <div>
          <dt>Plátci s konečným dokladem / evidovaní plátci</dt><dd>
            {metric_value(@snapshot, "billing", "settlement_final_accounts_count")} / {metric_value(
              @snapshot,
              "billing",
              "settlement_accounts_count"
            )}
          </dd>
        </div>
        <div>
          <dt>Chybějící konečné doklady</dt><dd>
            {get_in(@snapshot, ["sources", "billing", "quality", "missing_final_accounts"])}
          </dd>
        </div>
        <div>
          <dt>Pobyty bez účtu / nehotové rozdělení plátců</dt><dd>
            {get_in(@snapshot, ["sources", "billing", "quality", "bookings_without_accounts"])} / {get_in(
              @snapshot,
              ["sources", "billing", "quality", "incomplete_allocation_bookings"]
            )}
          </dd>
        </div>
        <div>
          <dt>Nejisté zařazení pobytů bez platného odjezdu</dt><dd>
            {get_in(@snapshot, ["sources", "billing", "quality", "uncertain_departure_bookings"])}
          </dd>
        </div>
        <div>
          <dt>Osobní účty · bez domýšlení ceny</dt><dd>
            {metric_value(@snapshot, "billing", "personal_accounts_count")}
          </dd>
        </div>
      </dl>
      <p class="adventure-muted">
        Zařazení podle společného data odjezdu rezervace, včetně vydané historie později zrušených či smazaných pobytů. Úhrady zahrnují i platby mimo sezónu a jsou aktuální k přepočtu. Záloha a její daňový doklad nejsou další výnos. Chybějící konečný doklad není vyúčtování nula; známý součet může být jen dílčí. Přeplatek jednoho plátce nesnižuje dluh druhého.
      </p>
    </details>
    """
  end

  attr :snapshot, :map, required: true
  attr :source, :string, required: true
  attr :metric, :string, required: true
  attr :label, :string, required: true
  attr :symbol, :string, required: true
  attr :note, :string, required: true
  attr :kind, :string, default: "number"

  defp chronicle_card(assigns) do
    source = get_in(assigns.snapshot, ["sources", assigns.source]) || %{}
    value = metric_value(assigns.snapshot, assigns.source, assigns.metric)

    quality =
      get_in(source, ["metric_metadata", assigns.metric, "completeness"]) ||
        get_in(source, ["quality", "completeness"]) || "partial"

    assigns =
      assign(assigns, value: value, quality: if(is_nil(value), do: "unavailable", else: quality))

    ~H"""
    <div class="adventure-metric" data-metric={@metric}>
      <span><.symbol name={@symbol} /> {@label}</span>
      <strong class="break-words">{case @kind do
        "money" ->
          money(@value)

        "percent" ->
          if is_nil(@value),
            do: "Nedostupné",
            else: CurrencyHelper.format_number(@value, precision: 1, decimal_separator: ",") <> " %"

        _ ->
          if is_nil(@value),
            do: "Nedostupné",
            else: CurrencyHelper.format_number(@value, precision: 0)
      end}</strong>
      <small>{@note}</small>
      <small>{case @quality do
        "complete" -> "Podklady úplné v rámci evidence"
        "unavailable" -> "Nedostupné podklady"
        _ -> "Dílčí podklady"
      end}</small>
    </div>
    """
  end

  defp metric_value(snapshot, source, metric),
    do: get_in(snapshot, ["sources", source, "metrics", metric])

  defp money(nil), do: "Nedostupné"
  defp money(value), do: CurrencyHelper.format_currency(Decimal.new(to_string(value)))

  attr :snapshot, :map, required: true

  defp source_details(assigns) do
    ~H"""
    <dl class="adventure-source-data">
      <div>
        <dt>Zdroj a verze</dt><dd>
          {@snapshot["source"] || "Adventure.Sources: stays / bar / billing"} · {@snapshot[
            "rules_version"
          ]}
        </dd>
      </div><div>
        <dt>Přepočteno</dt><dd>{@snapshot["as_of"]}</dd>
      </div><div>
        <dt>Hranice realizace</dt><dd>{@snapshot["cutoff_on"]} · Europe/Prague</dd>
      </div><div>
        <dt>
          Dokončené pobyty
          <span :if={@snapshot["rules_version"] == "stays_v1"}>/ způsobilé pro XP</span>
        </dt><dd>
          {CurrencyHelper.format_number(@snapshot["completed_stays"])}
          <span :if={@snapshot["rules_version"] == "stays_v1"}> / {@snapshot[
            "eligible_completed_stays"
          ]}</span>
        </dd>
      </div><div>
        <dt>Realizované / budoucí lůžkonoci</dt><dd>
          {CurrencyHelper.format_number(@snapshot["realized_bednights"])} / {CurrencyHelper.format_number(
            @snapshot["reserved_bednights"]
          )}
        </dd>
      </div><div>
        <dt>Úplnost / nejisté pobyty</dt><dd>
          {@snapshot["completeness"]} / {@snapshot["uncertain_stays"] ||
            get_in(@snapshot, ["sources", "stays", "quality", "uncertain_stays"])}
        </dd>
      </div><div>
        <dt>Kapacita</dt><dd>{@snapshot["capacity"]} · ručně potvrzená konstanta</dd>
      </div>
    </dl><p class="adventure-muted">{@snapshot["definition"]}</p>
    <details :for={{source, data} <- @snapshot["sources"] || %{}} class="adventure-audit-details">
      <summary>{source} · definice {data["definition_version"]}</summary>
      <p class="adventure-muted">
        Stav k {data["as_of"]} · Europe/Prague. Výsledek odpovídá evidenci v okamžiku přepočtu, ne rekonstrukci tehdejší databáze.
      </p>
      <dl class="adventure-source-data">
        <div :for={{metric, metadata} <- data["metric_metadata"] || %{}}>
          <dt class="break-all">{metric}</dt><dd>
            {metadata["completeness"]} · {metadata["unit"]} · období {get_in(metadata, [
              "period",
              "starts_on"
            ])} až {get_in(metadata, ["period", "ends_on"])}
            <span :if={metadata["time_basis"]}> · {metadata["time_basis"]}</span>
          </dd>
        </div>
      </dl>
    </details>
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

  defp historical_draft?(campaign, today),
    do:
      campaign.rules_version == "season_v1" &&
        Date.compare(campaign.ends_on, today) == :lt

  defp status("draft"), do: "Návrh"
  defp status("active"), do: "Aktivní"
  defp status("closed"), do: "Uzavřená"
  defp status("unlocked"), do: "Získáno"
  defp status("revoked"), do: "Odvoláno"
  defp status("locked"), do: "Zamčeno"
end
