defmodule CozyCheckoutWeb.BillingLive.Booking do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.{Billing, Bookings}
  alias CozyCheckout.Bookings.BookingInvoiceItem
  alias CozyCheckoutWeb.BillingLive.Helpers

  @buyer_fields [
    {"name", "Jméno / firma / škola"},
    {"street", "Ulice a číslo"},
    {"city", "Město"},
    {"postcode", "PSČ"},
    {"country", "Země (CZ)"},
    {"company_id", "IČO"},
    {"vat_id", "DIČ"},
    {"email", "Fakturační e-mail"}
  ]
  def mount(%{"booking_id" => id}, _, socket) do
    booking = Bookings.get_booking!(id)
    buyer = Billing.customer(id).data

    buyer =
      if buyer == %{},
        do: %{
          "name" => booking.guest.name,
          "email" => booking.guest.email || "",
          "country" => "CZ"
        },
        else: buyer

    {:ok,
     socket
     |> assign(
       booking: booking,
       page_title: "Fakturace pobytu",
       buyer_fields: @buyer_fields,
       buyer_form: to_form(buyer, as: :buyer),
       item_form: item_form(),
       editing: nil,
       pricing: nil,
       preview: nil,
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

  def handle_event("refresh", _, socket), do: {:noreply, refresh(socket)}

  def handle_event("customer", %{"buyer" => attrs}, socket),
    do:
      result(
        Billing.save_customer(socket.assigns.booking.id, attrs),
        assign(socket, :buyer_form, to_form(attrs, as: :buyer))
      )

  def handle_event("create", _, socket),
    do: result(Billing.create_calculation(socket.assigns.booking.id), socket)

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

  def handle_event("edit-item", %{"id" => id}, socket) do
    item = Enum.find(socket.assigns.calculation.items, &(&1.id == id))
    {:noreply, assign(socket, editing: id, item_form: item_form(item))}
  end

  def handle_event("cancel-item", _, socket),
    do: {:noreply, assign(socket, editing: nil, item_form: item_form())}

  def handle_event("save-item", %{"booking_invoice_item" => attrs}, socket) do
    case Billing.save_item(socket.assigns.booking.id, attrs, socket.assigns.editing) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(editing: nil, item_form: item_form(), preview: nil)
         |> refresh()
         |> put_flash(:info, "Položka uložena a přepočítána")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :item_form, to_form(cs))}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Helpers.error(error))}
    end
  end

  def handle_event("delete-item", %{"id" => id}, socket),
    do: result(Billing.delete_item(socket.assigns.booking.id, id), assign(socket, :preview, nil))

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

    assign(socket,
      calculation: Billing.calculation(id),
      pricing_hint: Billing.pricing_preview(id),
      documents: Billing.list_documents(%{"booking_id" => id}),
      payments: Billing.list_payments(id),
      balance: Billing.balance(id)
    )
  end

  defp item_form(
         item \\ %BookingInvoiceItem{
           name: "",
           quantity: 1,
           nights: 1,
           vat_rate: Decimal.new(12),
           item_type: "extra",
           tax_mode: "taxable"
         }
       ),
       do: to_form(BookingInvoiceItem.changeset(item, %{}))

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
    <Layouts.app flash={@flash}>
      <div class="max-w-6xl mx-auto space-y-6">
        <div class="flex justify-between flex-wrap gap-3">
          <h1 class="text-3xl font-bold">Fakturace pobytu – {@booking.guest.name}</h1><.link
            navigate={~p"/admin/bookings/#{@booking.id}"}
            class="btn"
          >Zpět na rezervaci</.link>
        </div>
        <p>{@booking.check_in_date} – {@booking.check_out_date || "odjezd není vyplněný"}</p>
        <nav class="flex gap-3">
          <.link navigate={~p"/admin/accommodation-prices"} class="link">Ceník ubytování</.link><.link
            navigate={~p"/admin/billing/settings"}
            class="link"
          >Dodavatel a číselné řady</.link><button class="link" phx-click="refresh">Obnovit přehled</button>
        </nav>
        <div class="bg-emerald-50 rounded-xl p-5 flex flex-wrap gap-8">
          <p><b>{Billing.payment_state(@balance)}</b></p>
          <p>
            Cena: <b>{if @balance.total, do: format_currency(@balance.total), else: "Chybí ceny"}</b>
          </p><p>Přijato po vratkách: <b>{format_currency(@balance.received)}</b></p><p :if={
            @balance.outstanding
          }>
            Zbývá / přeplatek: <b>{format_currency(@balance.outstanding)}</b>
          </p>
        </div>
        <section class="bg-white p-6 rounded-xl space-y-4">
          <h2 class="text-xl font-bold">Kalkulace a počty hostů</h2>
          <p>Upravitelný podklad pobytu. Změny neovlivňují již vystavené doklady.</p>
          <button :if={!@calculation} class="btn btn-primary" phx-click="create">Založit kalkulaci</button>
          <div :if={@calculation} class="space-y-4">
            <p :if={@calculation.pricing_basis == "legacy_net"} class="alert alert-warning">
              Původní interní podklad: ceny jsou bez DPH. Číslo {@calculation.invoice_number ||
                "nepřiděleno"}, stav {@calculation.state}. Nejde o nově vystavený doklad ani potvrzení platby.
            </p>
            <p :if={@calculation.pricing_basis == "gross"}>
              Ceny včetně DPH. Naceněno pro příjezd {@calculation.priced_on}.
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
            <div class="flex gap-2">
              <button class="btn" phx-click="pricing">Použít aktuální ceník – náhled</button><button
                :if={@documents == []}
                class="btn"
                phx-click="personal"
              >{if @calculation.state == "personal",
                do: "Zrušit osobní pobyt",
                else: "Označit osobní pobyt"}</button>
            </div>
            <p :if={@calculation.state == "personal"} class="alert">
              Osobní pobyt počítá hosty do obsazenosti; nevystavuje doklady.
            </p>
            <div class="overflow-x-auto">
              <table class="table">
                <thead>
                  <tr>
                    <th>Položka</th><th>Počet</th><th>Nocí / jednotek</th><th>Cena</th><th>DPH</th><th>
                      Celkem
                    </th><th></th>
                  </tr>
                </thead><tbody>
                  <tr :for={item <- @calculation.items}>
                    <td>
                      {item.name} <span :if={item.item_type == "person"} class="badge">Osoby</span>
                    </td><td>{item.quantity}</td><td>{item.nights}</td><td>
                      {if item.price_per_night,
                        do: format_currency(item.price_per_night),
                        else: "Chybí cena"}
                    </td><td>
                      {if item.tax_mode == "outside", do: "Mimo DPH", else: "#{item.vat_rate} %"}
                    </td><td>{if item.total, do: format_currency(item.total), else: "—"}</td><td>
                      <button class="btn btn-sm" phx-click="edit-item" phx-value-id={item.id}>Upravit</button><button
                        class="btn btn-sm"
                        phx-click="delete-item"
                        phx-value-id={item.id}
                        data-confirm="Odstranit položku kalkulace? U osob se změní obsazenost."
                      >Odstranit</button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <.form
              for={@item_form}
              id="billing-item"
              phx-submit="save-item"
              class="grid md:grid-cols-4 gap-3"
            >
              <h3 class="font-bold md:col-span-4">
                {if @editing, do: "Upravit položku", else: "Přidat položku / poplatek z pobytu"}
              </h3>
              <.input field={@item_form[:name]} label="Název" required />
              <.input
                field={@item_form[:item_type]}
                type="select"
                label="Typ"
                options={[{"Služba / poplatek", "extra"}, {"Osoby (obsazenost)", "person"}]}
              />
              <.input field={@item_form[:quantity]} type="number" label="Počet" min="0" required />
              <.input
                field={@item_form[:nights]}
                type="number"
                label="Počet nocí / jednotek"
                min="1"
                required
              />
              <.input
                field={@item_form[:price_per_night]}
                type="number"
                label={
                  if @calculation.pricing_basis == "gross",
                    do: "Jednotková cena vč. DPH",
                    else: "Jednotková cena bez DPH"
                }
                step="0.01"
                min="0"
              />
              <.input
                field={@item_form[:vat_rate]}
                type="select"
                label="Sazba DPH"
                options={[{"12 %", "12"}, {"21 %", "21"}, {"0 %", "0"}]}
              />
              <.input
                field={@item_form[:tax_mode]}
                type="select"
                label="Režim (poplatek: mimo DPH)"
                options={[{"Zdanitelné", "taxable"}, {"Mimo předmět DPH", "outside"}]}
              />
              <div class="flex gap-2 items-end">
                <button class="btn btn-primary">Uložit</button><button
                  class="btn"
                  type="button"
                  phx-click="cancel-item"
                >Zrušit</button>
              </div>
            </.form>
          </div>
          <div :if={@pricing} class="border rounded-lg p-4 space-y-3" id="pricing-preview">
            <h3 class="font-bold">Náhled přecenění podle příjezdu</h3>
            <p :if={!@pricing.season}>Chybí ceník.</p><p :if={@pricing.season}>
              Sezona {@pricing.season.name}, {@pricing.nights} nocí. Nové ceny jsou včetně DPH. Počty osob zůstanou zachované.
            </p>
            <p :for={row <- @pricing.rows}>
              {row.name}: {if row.old, do: format_currency(row.old), else: "chybí"} → {if row.price,
                do: format_currency(row.price),
                else: "chybí"}
            </p>
            <button :if={@pricing.season} class="btn btn-primary" phx-click="apply-pricing">Potvrdit nové ceny a počet nocí</button>
          </div>
        </section>
        <section class="bg-white rounded-xl p-6">
          <h2 class="text-xl font-bold mb-4">Odběratel</h2>
          <.form
            for={@buyer_form}
            id="billing-customer"
            phx-submit="customer"
            class="grid md:grid-cols-2 gap-3"
          >
            <.input :for={{key, label} <- @buyer_fields} field={@buyer_form[key]} label={label} /><button class="btn btn-primary md:col-span-2">Uložit odběratele</button>
          </.form>
        </section>
        <section class="bg-white rounded-xl p-6 space-y-4">
          <h2 class="text-xl font-bold">Vystavit doklad</h2>
          <.form
            for={@issue_form}
            id="billing-issue"
            phx-submit="preview"
            class="grid md:grid-cols-3 gap-3"
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
            <button class="btn btn-primary self-end">Zkontrolovat náhled</button>
          </.form>
          <div
            :if={@preview}
            class="border-2 border-emerald-300 rounded-xl p-4 space-y-3"
            id="document-preview"
          >
            <h3 class="font-bold">NÁHLED – {Billing.kind_label(@preview.kind)}</h3>
            <p>
              Odběratel: {@preview.snapshot["customer"]["name"]}. Datum vystavení: {@preview.issued_on}. Splatnost: {@preview.due_on}.
            </p>
            <p :for={line <- @preview.lines}>
              {line["name"]}: {line["quantity"]} × {line["nights"]} — {line["gross"]} CZK ({line[
                "vat_rate"
              ]} % DPH)
            </p>
            <p :for={line <- @preview.snapshot["deductions"]}>{line["name"]}: {line["gross"]} CZK</p>
            <p class="font-bold">
              Celkem {format_currency(@preview.total)}; po odpočtech {format_currency(
                Decimal.add(
                  @preview.total,
                  CozyCheckout.Billing.Money.total(@preview.snapshot["deductions"])
                )
              )}
            </p>
            <p>Vystavený doklad se uzamkne. PDF bude dostupné v detailu.</p>
            <button class="btn btn-primary" phx-click="issue" phx-disable-with="Vystavuji…">Vystavit doklad</button>
          </div>
        </section>
        <section class="bg-white rounded-xl p-6 space-y-4">
          <h2 class="text-xl font-bold">Doklady</h2>
          <p :if={@documents == []}>Zatím nebyl vystaven žádný doklad.</p>
          <div :for={doc <- @documents} class="flex justify-between flex-wrap border-b py-3">
            <div>
              <b>{doc.number}</b> – {Billing.kind_label(doc.kind)} · {format_currency(doc.total)}
            </div><.link navigate={~p"/admin/billing/documents/#{doc.id}"} class="link">Detail, PDF, odeslání a oprava</.link>
          </div>
        </section>
        <section class="bg-white rounded-xl p-6 space-y-4">
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
            <b>{if p.kind == "refund", do: "Vratka", else: "Příjem"}</b> {format_currency(p.amount)} · {p.paid_on} · {p.method} · {p.reference}<span :if={
              p.tax_document_id
            }> · doklad k platbě vystaven</span><span
              :if={p.tax_document_id && Date.diff(Billing.today(), p.paid_on) > 15}
              class="text-amber-700"
            > · zkontrolujte včasnost daňového dokladu</span>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
