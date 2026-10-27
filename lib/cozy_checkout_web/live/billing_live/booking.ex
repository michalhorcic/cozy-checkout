defmodule CozyCheckoutWeb.BillingLive.Booking do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.{Billing, Bookings}
  alias CozyCheckout.Billing.Presentation
  alias CozyCheckout.Bookings.BookingInvoiceItem
  alias CozyCheckoutWeb.BillingLive.Helpers

  @buyer_fields [
    {"street", "Ulice a číslo"},
    {"city", "Město"},
    {"postcode", "PSČ"},
    {"country", "Země"},
    {"company_id", "IČO"},
    {"vat_id", "DIČ"},
    {"email", "Fakturační e-mail"}
  ]
  def mount(%{"booking_id" => id}, _, socket) do
    if connected?(socket), do: Process.send_after(self(), :abra_tick, 10_000)
    booking = Bookings.get_booking!(id)
    buyer = Billing.customer(id).data

    buyer =
      if buyer == %{},
        do: %{
          "name" => booking.guest.name,
          "email" => booking.guest.email || "",
          "country" => "Česká Republika"
        },
        else: buyer

    buyer = Map.update(buyer, "country", "Česká Republika", &Presentation.country_name/1)

    {:ok,
     socket
     |> assign(
       booking: booking,
       page_title: "Fakturace pobytu",
       buyer_fields: @buyer_fields,
       buyer_form: to_form(buyer, as: :buyer),
       item_rows: nil,
       items_dirty?: false,
       pricing: nil,
       preview: nil,
       email_document: nil,
       email_form: nil,
       email_error: nil,
       issue_form:
         to_form(
           %{
             "kind" => "advance",
             "percent" => "50",
             "amount" => "",
             "tax_date" => to_string(booking.check_out_date || Billing.today()),
             "due_on" => ""
           },
           as: :issue
         ),
       payment_form: payment_form(),
       correction_form: to_form(%{}, as: :correction)
     )
     |> refresh()}
  end

  def handle_info(:abra_tick, socket) do
    Process.send_after(self(), :abra_tick, 10_000)

    {:noreply,
     assign(
       socket,
       :abra_transfers,
       CozyCheckout.Abra.Transfers.for_documents(socket.assigns.documents)
     )}
  end

  def handle_event("refresh", _, socket), do: {:noreply, refresh(socket)}

  def handle_event("compose-email", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.documents, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Doklad nepatří k této rezervaci")}

      document ->
        {:noreply,
         assign(socket,
           email_document: document,
           email_form: to_form(Helpers.email_defaults(document), as: :email),
           email_error: nil
         )}
    end
  end

  def handle_event("close-email", _, socket),
    do: {:noreply, assign(socket, email_document: nil, email_form: nil, email_error: nil)}

  def handle_event("email", _, %{assigns: %{email_document: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("email", %{"email" => attrs}, socket) do
    request_id = socket.assigns.email_form[:request_id].value
    attrs = Map.put(attrs, "request_id", request_id)

    case Billing.enqueue_email(socket.assigns.email_document.id, attrs, request_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(email_document: nil, email_form: nil, email_error: nil)
         |> put_flash(:info, "E-mail zařazen k odeslání")}

      {:error, error} ->
        {:noreply,
         assign(socket,
           email_form: to_form(attrs, as: :email),
           email_error: Helpers.error(error)
         )}
    end
  end

  def handle_event("customer", %{"buyer" => attrs}, socket),
    do:
      result(
        Billing.save_customer(socket.assigns.booking.id, attrs),
        assign(socket, :buyer_form, to_form(attrs, as: :buyer))
      )

  def handle_event("create", _, socket),
    do: result(Billing.create_calculation(socket.assigns.booking.id), socket)

  def handle_event(event, _, %{assigns: %{items_dirty?: true}} = socket)
      when event in ["preview", "issue", "pricing", "apply-pricing", "personal", "payment"] do
    {:noreply, put_flash(socket, :error, "Nejprve uložte nebo zahoďte změny kalkulace.")}
  end

  def handle_event("pricing", _, socket),
    do: {:noreply, assign(socket, :pricing, Billing.pricing_preview(socket.assigns.booking.id))}

  def handle_event("apply-pricing", _, socket) do
    result(
      Billing.apply_pricing(socket.assigns.booking.id, socket.assigns.pricing.token),
      assign(socket, pricing: nil, preview: nil)
    )
  end

  def handle_event("personal", _, socket),
    do:
      result(
        Billing.set_personal(
          socket.assigns.booking.id,
          socket.assigns.calculation.state != "personal"
        ),
        socket
      )

  def handle_event("change-items", params, socket),
    do: {:noreply, update_item_rows(socket, params)}

  def handle_event("add-item", _, socket) do
    row =
      editor_row(%BookingInvoiceItem{
        name: "",
        quantity: 1,
        nights: 1,
        vat_rate: Decimal.new(12),
        item_type: "extra",
        tax_mode: "taxable",
        position: length(socket.assigns.item_rows)
      })

    {:noreply, socket |> assign(:item_rows, socket.assigns.item_rows ++ [row]) |> editor_state()}
  end

  def handle_event("remove-item", %{"id" => key}, socket) do
    rows =
      Enum.flat_map(socket.assigns.item_rows, fn row ->
        cond do
          row.key != key -> [row]
          is_nil(row.changeset.data.id) -> []
          true -> [%{row | deleted?: true}]
        end
      end)

    {:noreply, socket |> assign(:item_rows, rows) |> editor_state()}
  end

  def handle_event("restore-item", %{"id" => key}, socket) do
    rows =
      Enum.map(socket.assigns.item_rows, fn row ->
        if row.key == key, do: %{row | deleted?: false}, else: row
      end)

    {:noreply, socket |> assign(:item_rows, rows) |> editor_state()}
  end

  def handle_event("discard-items", _, socket),
    do:
      {:noreply, socket |> assign(item_rows: nil, items_dirty?: false, preview: nil) |> refresh()}

  def handle_event("save-items", params, socket) do
    socket = update_item_rows(socket, params)
    rows = socket.assigns.item_rows

    if Enum.all?(rows, &(&1.deleted? or &1.changeset.valid?)) do
      batch =
        Enum.map(rows, fn row ->
          %{id: row.changeset.data.id, delete: row.deleted?, attrs: row.changeset.params || %{}}
        end)

      case Billing.save_calculation_items(
             socket.assigns.booking.id,
             batch,
             socket.assigns.items_version
           ) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(item_rows: nil, items_dirty?: false, preview: nil, pricing: nil)
           |> refresh()
           |> put_flash(:info, "Změny kalkulace uloženy")}

        {:error, error} ->
          {:noreply, put_flash(socket, :error, Helpers.error(error))}
      end
    else
      {:noreply, put_flash(socket, :error, "Opravte označená pole. Změny nebyly uloženy.")}
    end
  end

  def handle_event("preview", %{"issue" => attrs}, socket) do
    attrs = if attrs["due_on"] == "", do: Map.delete(attrs, "due_on"), else: attrs
    socket = assign(socket, :issue_form, to_form(attrs, as: :issue))

    case Billing.preview(socket.assigns.booking.id, attrs["kind"], attrs) do
      {:ok, preview} ->
        {:noreply,
         assign(socket,
           preview: preview,
           preview_attrs: Map.put(attrs, "preview_token", preview.token),
           issue_request: Ecto.UUID.generate()
         )}

      {:error, error} ->
        {:noreply, socket |> assign(:preview, nil) |> put_flash(:error, Helpers.error(error))}
    end
  end

  def handle_event("issue", _, %{assigns: %{preview: nil}} = socket), do: {:noreply, socket}

  def handle_event("issue", _, socket) do
    case Billing.issue(
           socket.assigns.booking.id,
           socket.assigns.preview.kind,
           socket.assigns.preview_attrs,
           socket.assigns.issue_request
         ) do
      {:ok, doc} ->
        {:noreply,
         socket
         |> assign(:preview, nil)
         |> refresh()
         |> put_flash(:info, "Vystaveno #{doc.number}")}

      {:error, error} ->
        {:noreply, socket |> assign(:preview, nil) |> put_flash(:error, Helpers.error(error))}
    end
  end

  def handle_event("payment", %{"payment" => attrs}, socket) do
    attrs = if attrs["document_id"] == "", do: Map.delete(attrs, "document_id"), else: attrs

    case Billing.record_payment(socket.assigns.booking.id, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:payment_form, payment_form())
         |> refresh()
         |> put_flash(:info, "Platba zaznamenána")}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:payment_form, to_form(attrs, as: :payment))
         |> put_flash(:error, Helpers.error(error))}
    end
  end

  defp result({:ok, _}, socket),
    do: {:noreply, socket |> refresh() |> put_flash(:info, "Uloženo")}

  defp result({:error, error}, socket),
    do: {:noreply, put_flash(socket, :error, Helpers.error(error))}

  defp refresh(socket) do
    id = socket.assigns.booking.id

    calculation = Billing.calculation(id)
    documents = Billing.list_documents(%{"booking_id" => id})

    socket =
      assign(socket,
        personal?: match?(%{state: "personal"}, calculation),
        calculation: calculation,
        pricing_hint: Billing.pricing_preview(id),
        documents: documents,
        abra_transfers: CozyCheckout.Abra.Transfers.for_documents(documents),
        payments: Billing.list_payments(id),
        bank_suggestions: CozyCheckout.Abra.Bank.for_booking(id),
        bank_import: CozyCheckout.Abra.Bank.status(),
        balance: Billing.balance(id)
      )

    if calculation && (is_nil(socket.assigns.item_rows) or !socket.assigns.items_dirty?) do
      socket
      |> assign(
        item_rows: Enum.map(calculation.items, &editor_row/1),
        items_version: Billing.calculation_version(calculation)
      )
      |> editor_state()
    else
      socket
    end
  end

  defp editor_row(item) do
    %{
      key: item.id || Ecto.UUID.generate(),
      changeset: BookingInvoiceItem.changeset(item, %{}),
      deleted?: false
    }
  end

  defp update_item_rows(socket, params) do
    inputs = Map.get(params, "items", %{})

    rows =
      Enum.map(socket.assigns.item_rows, fn row ->
        case inputs[row.key] do
          nil ->
            row

          attrs ->
            %{
              row
              | changeset: %{
                  BookingInvoiceItem.changeset(row.changeset.data, attrs)
                  | action: :validate
                }
            }
        end
      end)

    socket |> assign(:item_rows, rows) |> editor_state()
  end

  defp editor_state(socket) do
    dirty? =
      Enum.any?(socket.assigns.item_rows, fn row ->
        row.deleted? or is_nil(row.changeset.data.id) or !row.changeset.valid? or
          map_size(row.changeset.changes) > 0
      end)

    assign(socket,
      items_dirty?: dirty?,
      preview: if(dirty?, do: nil, else: socket.assigns.preview),
      pricing: if(dirty?, do: nil, else: socket.assigns.pricing)
    )
  end

  defp row_form(row), do: to_form(row.changeset, as: "items[#{row.key}]", id: "item-#{row.key}")

  defp row_total(row, basis) do
    item = Ecto.Changeset.apply_changes(row.changeset)

    if row.changeset.valid? and item.price_per_night do
      CozyCheckout.Billing.Money.line(
        item.name,
        item.quantity,
        item.nights,
        item.price_per_night,
        item.vat_rate,
        item.tax_mode,
        basis
      )
      |> CozyCheckout.Billing.Money.value("gross")
    end
  end

  defp editor_total(rows, basis) do
    active = Enum.reject(rows, & &1.deleted?)

    if Enum.all?(active, fn row ->
         row.changeset.valid? and
           (row_total(row, basis) != nil or
              Ecto.Changeset.get_field(row.changeset, :quantity) == 0)
       end) do
      active
      |> Enum.map(&(row_total(&1, basis) || Decimal.new(0)))
      |> CozyCheckout.Billing.Money.sum()
    end
  end

  defp payment_form,
    do:
      to_form(
        %{
          "request_id" => Ecto.UUID.generate(),
          "kind" => "receipt",
          "paid_on" => to_string(Billing.today()),
          "method" => "bank",
          "amount" => "",
          "reference" => "",
          "document_id" => ""
        },
        as: :payment
      )

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      content_class="mx-auto w-full max-w-7xl space-y-6"
      main_class="px-4 py-6 sm:px-6 lg:px-8 lg:py-8"
    >
      <div id="billing-workspace" class="min-w-0 space-y-6">
        <div class="flex justify-between flex-wrap gap-3">
          <h1 class="text-3xl font-bold">Fakturace pobytu – {@booking.guest.name}</h1><.link
            navigate={~p"/admin/bookings/#{@booking.id}"}
            class="btn"
          >Zpět na rezervaci</.link>
        </div>
        <p class="text-primary-400">
          {Presentation.date(@booking.check_in_date)} – {if @booking.check_out_date,
            do: Presentation.date(@booking.check_out_date),
            else: "Odjezd není vyplněný"}
        </p>
        <nav class="flex flex-wrap items-center gap-x-5 gap-y-2 text-sm">
          <button class="link" phx-click="refresh">Obnovit přehled</button>
        </nav>
        <p
          :if={@personal?}
          id="billing-personal"
          class={["rounded-xl bg-secondary-50 p-5 font-semibold"]}
        >
          Soukromý pobyt · bez finanční evidence
        </p>
        <div
          :if={not @personal?}
          class="grid gap-4 rounded-xl border border-secondary-200 bg-secondary-50 p-5 sm:grid-cols-2 xl:grid-cols-4"
        >
          <p><b>{Billing.payment_state(@balance)}</b></p>
          <p>
            Cena:
            <b>{if @balance.total, do: Presentation.amount(@balance.total), else: "Chybí ceny"}</b>
          </p><p>Přijato po vratkách: <b>{Presentation.amount(@balance.received)}</b></p><p :if={
            @balance.outstanding
          }>
            {Presentation.balance_label(@balance.outstanding)}:
            <b>{Presentation.balance_amount(@balance.outstanding)}</b>
          </p>
        </div>
        <section
          id="billing-calculation"
          class="min-w-0 rounded-xl border border-secondary-200 bg-white p-4 space-y-5 sm:p-6"
        >
          <h2 class="text-xl font-bold">Kalkulace a počty hostů</h2>
          <p>Upravitelný podklad pobytu. Změny neovlivňují již vystavené doklady.</p>
          <button :if={!@calculation} class="btn btn-primary" phx-click="create">Založit kalkulaci</button>
          <div :if={@calculation} class="space-y-4">
            <p :if={@calculation.pricing_basis == "legacy_net"} class="alert alert-warning">
              Původní interní podklad: ceny jsou bez DPH. Číslo {@calculation.invoice_number ||
                "nepřiděleno"}, stav {@calculation.state}. Nejde o nově vystavený doklad ani potvrzení platby.
            </p>
            <p :if={@calculation.pricing_basis == "gross"}>
              Ceny včetně DPH. Naceněno pro příjezd {Presentation.date(@calculation.priced_on)}.
            </p>
            <p :if={@pricing_hint.changed_date} class="alert alert-warning">
              Datum příjezdu se změnilo. Zkontrolujte ceník a počet nocí; ceny nebyly automaticky změněny.
            </p>
            <p :if={@pricing_hint.changed_nights} class="alert alert-warning">
              Počet nocí v kalkulaci se liší od délky pobytu. Zkontrolujte jej nebo potvrďte přepočet podle aktuálního ceníku.
            </p>
            <p :if={!@pricing_hint.season} class="alert alert-warning">
              Pro datum příjezdu chybí sezonní ceník. Ceny můžete doplnit ručně.
            </p>
            <div class="flex flex-wrap gap-2">
              <button class="btn" phx-click="pricing" disabled={@items_dirty?}>Použít aktuální ceník – náhled</button><button
                :if={@documents == []}
                class="btn"
                phx-click="personal"
                disabled={@items_dirty?}
              >{if @calculation.state == "personal",
                do: "Zrušit soukromý pobyt",
                else: "Označit soukromý pobyt"}</button>
            </div>
            <p :if={@calculation.state == "personal"} class="alert">
              Soukromý pobyt počítá hosty do obsazenosti; doklady ani platby se neevidují.
            </p>
            <.form
              for={%{}}
              id="billing-items-form"
              phx-change="change-items"
              phx-submit="save-items"
              phx-hook="CalculationEditor"
              data-dirty={to_string(@items_dirty?)}
              class="space-y-3"
            >
              <div id="billing-items" class="space-y-3">
                <div
                  class="hidden gap-3 px-4 text-sm font-semibold text-primary-400 md:grid md:grid-cols-[minmax(140px,2fr)_80px_100px_130px_110px]"
                  aria-hidden="true"
                >
                  <span>Položka</span><span class="text-right">Počet</span><span class="text-right">Nocí / jednotek</span><span class="text-right">Cena</span><span class="text-right">Celkem</span>
                </div>
                <div
                  :for={row <- @item_rows}
                  id={"billing-item-#{row.key}"}
                  class={[
                    "rounded-lg border p-4",
                    cond do
                      row.deleted? ->
                        "border-secondary-200 bg-secondary-50"

                      is_nil(row.changeset.data.id) or map_size(row.changeset.changes) > 0 or
                          !row.changeset.valid? ->
                        "border-amber-300 bg-amber-50/30"

                      true ->
                        "border-secondary-200 bg-white"
                    end
                  ]}
                >
                  <% form = row_form(row) %>
                  <div
                    :if={row.deleted?}
                    class="flex flex-wrap items-center justify-between gap-2 text-sm"
                  >
                    <span><s>{Ecto.Changeset.get_field(row.changeset, :name)}</s>
                    · Bude odstraněno po uložení</span>
                    <button
                      type="button"
                      class="btn btn-sm btn-ghost"
                      phx-click="restore-item"
                      phx-value-id={row.key}
                    >Vrátit</button>
                  </div>
                  <div :if={!row.deleted?}>
                    <div class="grid grid-cols-2 items-start gap-x-3 gap-y-2 md:[&_.label]:sr-only md:[&_.fieldset]:mb-0 md:grid-cols-[minmax(140px,2fr)_80px_100px_130px_110px]">
                      <div class="col-span-2 self-center md:col-span-1">
                        <p class="font-semibold break-words">
                          {Ecto.Changeset.get_field(row.changeset, :name) || "Nová položka"}
                        </p>
                        <span :if={is_nil(row.changeset.data.id)} class="text-xs text-primary-400">Nová položka</span>
                      </div>
                      <.input
                        field={form[:quantity]}
                        type="number"
                        label="Počet"
                        aria-label={"Počet – #{row.changeset.data.name || "nová položka"}"}
                        min="0"
                        required
                        class="input w-full text-right tabular-nums"
                      />
                      <.input
                        field={form[:nights]}
                        type="number"
                        label="Nocí / jednotek"
                        min="1"
                        required
                        class="input w-full text-right tabular-nums"
                      />
                      <.input
                        field={form[:price_per_night]}
                        type="number"
                        label={
                          if @calculation.pricing_basis == "gross",
                            do: "Cena vč. DPH",
                            else: "Cena bez DPH"
                        }
                        step="0.01"
                        min="0"
                        placeholder="Chybí cena"
                        class="input w-full text-right tabular-nums"
                      />
                      <div class="self-center text-right tabular-nums" aria-live="polite">
                        <span class="block text-xs text-primary-400 md:hidden">Celkem</span>
                        <b>{if total = row_total(row, @calculation.pricing_basis),
                          do: Presentation.amount(total),
                          else: "—"}</b>
                      </div>
                    </div>
                    <details
                      id={"item-details-#{row.key}"}
                      open={is_nil(row.changeset.data.id)}
                      class="mt-2"
                    >
                      <summary class="cursor-pointer text-sm text-primary-400 hover:text-primary-700">
                        Podrobnosti · {if Ecto.Changeset.get_field(row.changeset, :tax_mode) ==
                                            "outside",
                                          do: "Mimo DPH",
                                          else:
                                            "DPH #{Presentation.number(Ecto.Changeset.get_field(row.changeset, :vat_rate))} %"}
                      </summary>
                      <div class="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                        <.input field={form[:name]} label="Název" required />
                        <.input
                          field={form[:item_type]}
                          type="select"
                          label="Typ"
                          options={[{"Služba / poplatek", "extra"}, {"Osoby (obsazenost)", "person"}]}
                        />
                        <.input
                          field={form[:vat_rate]}
                          type="number"
                          label="Sazba DPH (%)"
                          min="0"
                          max="100"
                          step="0.01"
                          required
                        />
                        <.input
                          field={form[:tax_mode]}
                          type="select"
                          label="Režim DPH"
                          options={[{"Zdanitelné", "taxable"}, {"Mimo předmět DPH", "outside"}]}
                        />
                      </div>
                      <button
                        type="button"
                        class="btn btn-sm btn-ghost mt-2 text-red-700"
                        phx-click="remove-item"
                        phx-value-id={row.key}
                      >Odstranit položku</button>
                      <p
                        :if={row.changeset.action && !row.changeset.valid?}
                        class="mt-2 text-sm text-red-700"
                      >
                        Zkontrolujte označená pole.
                      </p>
                    </details>
                  </div>
                </div>
              </div>
              <button
                type="button"
                id="billing-add-item"
                class="btn btn-sm btn-ghost"
                phx-click="add-item"
              ><.icon name="hero-plus" class="size-4" />Přidat položku</button>
              <div class={[
                "flex flex-wrap items-center justify-between gap-3 rounded-lg border border-secondary-200 bg-secondary-50 p-4",
                @items_dirty? && "sticky bottom-3 z-10 shadow-sm"
              ]}>
                <div aria-live="polite">
                  <p class="font-semibold">
                    Celkem: {if total = editor_total(@item_rows, @calculation.pricing_basis),
                      do: Presentation.amount(total),
                      else: "Doplňte ceny a opravte chyby"}
                  </p>
                  <p id="billing-items-status" class="text-sm text-primary-400">
                    {if @items_dirty?, do: "Máte neuložené změny", else: "Všechny změny jsou uloženy"}
                  </p>
                </div>
                <div class="flex flex-wrap gap-2">
                  <button
                    type="button"
                    id="billing-discard-items"
                    class="btn"
                    phx-click="discard-items"
                    disabled={!@items_dirty?}
                  >Zahodit změny</button>
                  <button
                    id="billing-save-items"
                    class="btn btn-primary"
                    disabled={!@items_dirty?}
                    phx-disable-with="Ukládám…"
                  >Uložit změny</button>
                </div>
              </div>
            </.form>
          </div>
          <div :if={@pricing} class="border rounded-lg p-4 space-y-3" id="pricing-preview">
            <h3 class="font-bold">Náhled přecenění podle příjezdu</h3>
            <p :if={!@pricing.season}>Chybí ceník.</p><p :if={@pricing.season}>
              Sezona {@pricing.season.name}, {@pricing.nights} nocí. Nové ceny jsou včetně DPH. Počty osob zůstanou zachované.
            </p>
            <p :for={row <- @pricing.rows}>
              {row.name}: {if row.old, do: Presentation.amount(row.old), else: "chybí"} → {if row.price,
                do: Presentation.amount(row.price),
                else: "chybí"}
            </p>
            <button :if={@pricing.season} class="btn btn-primary" phx-click="apply-pricing">Potvrdit nové ceny a počet nocí</button>
          </div>
        </section>
        <div :if={not @personal?} class="grid items-start gap-6 xl:grid-cols-2">
          <section class="min-w-0 rounded-xl border border-secondary-200 bg-white p-4 sm:p-6">
            <h2 class="text-xl font-bold mb-4">Odběratel</h2>
            <.form
              for={@buyer_form}
              id="billing-customer"
              phx-submit="customer"
              class="grid md:grid-cols-2 gap-3"
            >
              <div class="md:col-span-2">
                <.input field={@buyer_form[:name]} label="Jméno / firma / škola" required />
                <p class="text-sm text-primary-400">
                  Pro vystavení dokladu stačí jméno nebo název odběratele.
                </p>
              </div>
              <details id="billing-customer-details" class="md:col-span-2">
                <summary class="cursor-pointer text-sm text-primary-400 hover:text-primary-700">
                  Další údaje <span class="text-xs">(nepovinné)</span>
                </summary>
                <div class="mt-3 grid gap-3 md:grid-cols-2">
                  <.input :for={{key, label} <- @buyer_fields} field={@buyer_form[key]} label={label} />
                </div>
              </details>
              <button class="btn btn-primary md:col-span-2">Uložit odběratele</button>
            </.form>
          </section>
          <section class="min-w-0 rounded-xl border border-secondary-200 bg-white p-4 space-y-4 sm:p-6">
            <h2 class="text-xl font-bold">Vystavit doklad</h2>
            <.form
              for={@issue_form}
              id="billing-issue"
              phx-submit="preview"
              class="grid gap-4 sm:grid-cols-2"
            >
              <.input
                field={@issue_form[:kind]}
                type="select"
                label="Druh"
                options={[{"Zálohová výzva", "advance"}, {"Konečná faktura", "final"}]}
              />
              <.input
                field={@issue_form[:percent]}
                type="number"
                step="0.01"
                label="Záloha v %"
                min="0"
                max="100"
              />
              <.input
                field={@issue_form[:amount]}
                type="number"
                step="0.01"
                label="Nebo částka zálohy (má přednost)"
                min="0"
              />
              <.input
                field={@issue_form[:tax_date]}
                type="date"
                label="DUZP konečné faktury"
                required
              />
              <.input
                field={@issue_form[:due_on]}
                type="date"
                label="Splatnost (prázdné = výchozí)"
              />
              <p :if={@items_dirty?} class="text-sm text-amber-700 sm:col-span-2">
                Před vystavením dokladu uložte nebo zahoďte změny kalkulace.
              </p>
              <button class="btn btn-primary self-end sm:col-span-2" disabled={@items_dirty?}>Zkontrolovat náhled</button>
            </.form>
          </section>
        </div>
        <section
          :if={@preview && not @personal?}
          class="border-2 border-emerald-300 rounded-xl p-4 space-y-3"
          id="document-preview"
        >
          <h3 class="font-bold">NÁHLED – {Billing.kind_label(@preview.kind)}</h3>
          <p>
            Odběratel: {@preview.snapshot["customer"]["name"]}. Datum vystavení: {Presentation.date(
              @preview.issued_on
            )}.
            <span :if={@preview.kind != "tax_receipt"}>Splatnost: {Presentation.date(@preview.due_on)}.</span>
            Pobyt: {Presentation.date(@preview.snapshot["check_in"])} – {Presentation.date(
              @preview.snapshot["check_out"]
            )}.
          </p>
          <CozyCheckoutWeb.BillingComponents.advance_breakdown
            id="advance-preview-breakdown"
            document={@preview}
          />
          <p
            :for={line <- Presentation.lines(@preview)}
            :if={is_nil(Presentation.advance_breakdown(@preview))}
          >
            {Presentation.line_label(line, @preview.kind)}:
            <span :if={@preview.kind not in ["advance", "tax_receipt"]}>
              {Presentation.number(line["quantity"])} × {Presentation.number(line["nights"])} —
            </span>
            {Presentation.amount(line["gross"])}
            <span :if={@preview.kind != "advance"}>
              {if line["tax_mode"] == "outside",
                do: "(mimo předmět DPH)",
                else: "(#{Presentation.number(line["vat_rate"])} % DPH)"}
            </span>
          </p>
          <p :for={line <- @preview.snapshot["deductions"]}>
            {line["name"]}: {Presentation.amount(line["gross"])}
          </p>
          <p :if={@preview.kind == "advance"} class="font-bold">
            Požadovaná záloha: {Presentation.amount(@preview.total)}
          </p>
          <p :if={@preview.kind != "advance"} class="font-bold">
            Celkem {Presentation.amount(@preview.total)}; po odpočtech {Presentation.amount(
              Decimal.add(
                @preview.total,
                CozyCheckout.Billing.Money.total(@preview.snapshot["deductions"])
              )
            )}
          </p>
          <p>Vystavený doklad se uzamkne. PDF a odeslání e-mailem najdete níže u dokladu.</p>
          <button class="btn btn-primary" phx-click="issue" phx-disable-with="Vystavuji…">Vystavit doklad</button>
        </section>
        <section
          :if={not @personal?}
          id="billing-documents"
          class="min-w-0 rounded-xl border border-secondary-200 bg-white p-4 space-y-4 sm:p-6"
        >
          <div class="flex items-center justify-between gap-3">
            <h2 class="text-xl font-bold">Doklady</h2>
            <.link navigate={~p"/admin/billing/transfers"} class="link text-sm">Přenosy do ABRA</.link>
            <span class="text-sm text-primary-400">Počet: {length(@documents)}</span>
          </div>
          <p :if={@documents == []} class="text-primary-400">Zatím nebyl vystaven žádný doklad.</p>
          <div
            :for={doc <- @documents}
            id={"billing-document-#{doc.id}"}
            class="flex flex-col gap-4 rounded-lg border border-secondary-200 p-4 lg:flex-row lg:items-center lg:justify-between"
          >
            <div class="min-w-0">
              <p class="font-semibold break-words">{doc.number}</p>
              <p class="mt-1 text-sm text-primary-400">
                {Billing.kind_label(doc.kind)} · {Presentation.date(doc.issued_on)}
              </p>
              <p class="mt-2 font-semibold tabular-nums">{Presentation.amount(doc.total)}</p>
              <CozyCheckoutWeb.BillingComponents.abra_status
                document={doc}
                statuses={Map.get(@abra_transfers, doc.id, [])}
              />
            </div>
            <div class="flex flex-wrap items-center gap-2">
              <.link
                id={"billing-document-pdf-#{doc.id}"}
                href={~p"/admin/billing/documents/#{doc.id}/pdf"}
                target="_blank"
                rel="noopener"
                class="btn btn-sm"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" />Stáhnout PDF
              </.link>
              <button
                id={"billing-document-email-#{doc.id}"}
                type="button"
                class="btn btn-sm btn-primary"
                phx-click="compose-email"
                phx-value-id={doc.id}
              >
                <.icon name="hero-envelope" class="size-4" />Odeslat e-mailem
              </button>
              <.link
                id={"billing-document-detail-#{doc.id}"}
                navigate={~p"/admin/billing/documents/#{doc.id}"}
                class="btn btn-sm btn-ghost"
              >Detail a historie</.link>
            </div>
          </div>
        </section>
        <section
          :if={not @personal?}
          class="min-w-0 rounded-xl border border-secondary-200 bg-white p-4 space-y-4 sm:p-6"
        >
          <div id="booking-bank-suggestions" class="space-y-3">
            <h2 class="text-xl font-bold">Návrhy bankovních plateb podle VS</h2>
            <p>
              Informativní návrhy nepotvrzují přijetí peněz. Dostupnost pohybu pro párování není ověřena.
            </p>
            <p
              :if={@bank_import && (@bank_import.scan_id || @bank_import.error)}
              class="text-amber-700"
            >
              Poslední načítání banky není dokončené. Návrhy mohou být neaktuální.
            </p>
            <.link navigate={~p"/admin/billing/bank"} class="link">Bankovní pohyby a stav načítání</.link>
            <div :for={row <- @bank_suggestions} class="rounded-lg border p-3">
              <p>
                {Presentation.amount(row.movement.amount)} · {Presentation.date(row.movement.paid_on)} · {row.movement.counterparty} · VS {row.movement.variable_symbol}
              </p>
              <p>
                Cílový doklad: {row.document.number} · rozdíl {Presentation.amount(row.difference)}
              </p>
              <p>{row.reason}</p>
            </div>
          </div>
          <h2 class="text-xl font-bold">Skutečně přijaté platby a vratky</h2>
          <p>
            Před vyúčtováním vznikne k přijaté záloze daňový doklad. Při vracení zdaněné zálohy nejprve vystavte opravu. Vratka pouze eviduje provedený převod.
          </p>
          <.form
            for={@payment_form}
            id="billing-payment"
            phx-submit="payment"
            class="grid md:grid-cols-3 gap-3"
          >
            <input type="hidden" name="payment[request_id]" value={@payment_form[:request_id].value} />
            <.input
              field={@payment_form[:kind]}
              type="select"
              label="Typ"
              options={[{"Příjem", "receipt"}, {"Vratka", "refund"}]}
            />
            <.input
              field={@payment_form[:amount]}
              type="number"
              label="Částka"
              step="0.01"
              min="0.01"
              required
            />
            <.input field={@payment_form[:paid_on]} type="date" label="Datum platby" required />
            <.input
              field={@payment_form[:method]}
              type="select"
              label="Způsob"
              options={[{"Bankovní převod", "bank"}, {"Hotově", "cash"}, {"Kartou", "card"}]}
            />
            <.input field={@payment_form[:reference]} label="Reference / poznámka" />
            <.input
              field={@payment_form[:document_id]}
              type="select"
              label="Přiřazení"
              options={
                ([{"Bez výzvy / automaticky konečné faktuře", ""}] ++
                   Enum.filter(@documents, &(&1.kind in ["advance", "final", "correction"])))
                |> Enum.map(fn d -> if is_tuple(d), do: d, else: {d.number, d.id} end)
              }
            />
            <button class="btn btn-primary md:col-span-3" phx-disable-with="Ukládám…">Zapsat skutečnou platbu</button>
          </.form>
          <div :for={p <- @payments} class="border-b py-2">
            <b>{if p.kind == "refund", do: "Vratka", else: "Příjem"}</b> {Presentation.amount(
              p.amount
            )} · {Presentation.date(p.paid_on)} · {p.method} · {p.reference}<span :if={
              p.tax_document_id
            }> · doklad k platbě vystaven</span><span
              :if={p.tax_document_id && Date.diff(Billing.today(), p.paid_on) > 15}
              class="text-amber-700"
            > · zkontrolujte včasnost daňového dokladu</span>
          </div>
        </section>
        <.modal :if={@email_document} id="billing-email-modal" show on_cancel={JS.push("close-email")}>
          <h2 id="billing-email-modal-title" class="pr-10 text-xl font-bold">
            Odeslat doklad e-mailem
          </h2>
          <p id="billing-email-modal-description" class="mt-2 mb-6 text-sm text-primary-400">
            {Billing.kind_label(@email_document.kind)} {@email_document.number} · {Presentation.amount(
              @email_document.total
            )}
          </p>
          <CozyCheckoutWeb.BillingComponents.email_form
            id="billing-booking-email"
            form={@email_form}
            error={@email_error}
          />
        </.modal>
      </div>
    </Layouts.app>
    """
  end
end
