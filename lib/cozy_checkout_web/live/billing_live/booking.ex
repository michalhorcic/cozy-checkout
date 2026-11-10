defmodule CozyCheckoutWeb.BillingLive.Booking do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.{Billing, Bookings, Guests}
  alias CozyCheckout.Billing.{BookingSummary, Presentation}
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
  def mount(%{"booking_id" => id} = params, _, socket) do
    if connected?(socket), do: Process.send_after(self(), :abra_tick, 10_000)
    booking = Bookings.get_booking!(id)

    payer =
      if params["payer"], do: Billing.get_account!(id, params["payer"]), else: Billing.account(id)

    buyer = Billing.customer(payer).data

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
       billing_scope: payer,
       account_form: nil,
       editing_account_id: nil,
       payer_search: "",
       payer_guest_search: "",
       payer_guest_suggestions: [],
       page_title: "Fakturace pobytu",
       buyer_fields: @buyer_fields,
       buyer_form: to_form(buyer, as: :buyer),
       item_rows: nil,
       items_dirty?: false,
       pricing: nil,
       preview: nil,
       manual_document: nil,
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

  def handle_info({:manual_delivery_changed, _id}, socket) do
    {:noreply,
     socket
     |> assign(
       :manual_delivery_summaries,
       Billing.manual_delivery_summaries(socket.assigns.documents)
     )
     |> put_flash(:info, "Evidence ručního odeslání byla uložena")}
  end

  def handle_event("manual-delivery", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.documents, &(&1.id == id)) do
      nil -> {:noreply, put_flash(socket, :error, "Doklad nepatří k této rezervaci")}
      doc -> {:noreply, assign(socket, :manual_document, doc)}
    end
  end

  def handle_event("close-manual-delivery", _, socket),
    do: {:noreply, assign(socket, :manual_document, nil)}

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
        Billing.save_customer(socket.assigns.billing_scope, attrs),
        assign(socket, :buyer_form, to_form(attrs, as: :buyer))
      )

  def handle_event("create", _, socket),
    do: result(Billing.create_calculation(socket.assigns.billing_scope), socket)

  def handle_event(event, _, %{assigns: %{items_dirty?: true}} = socket)
      when event in ["preview", "issue", "pricing", "apply-pricing", "personal", "payment"] do
    {:noreply, put_flash(socket, :error, "Nejprve uložte nebo zahoďte změny kalkulace.")}
  end

  def handle_event("pricing", _, socket),
    do:
      {:noreply, assign(socket, :pricing, Billing.pricing_preview(socket.assigns.billing_scope))}

  def handle_event("apply-pricing", _, socket) do
    result(
      Billing.apply_pricing(socket.assigns.billing_scope, socket.assigns.pricing.token),
      assign(socket, pricing: nil, preview: nil)
    )
  end

  def handle_event("personal", _, socket),
    do:
      result(
        Billing.set_personal(
          socket.assigns.billing_scope,
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
             socket.assigns.billing_scope,
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

    case Billing.preview(socket.assigns.billing_scope, attrs["kind"], attrs) do
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
           socket.assigns.billing_scope,
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

    case Billing.record_payment(socket.assigns.billing_scope, attrs) do
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

  def handle_event("select_account", %{"id" => id}, socket) do
    payer = Billing.get_account!(socket.assigns.booking.id, id)
    buyer = Billing.customer(payer).data

    {:noreply,
     socket
     |> assign(
       billing_scope: payer,
       buyer_form: to_form(buyer, as: :buyer),
       item_rows: nil,
       items_dirty?: false,
       preview: nil,
       pricing: nil,
       payment_form: payment_form(),
       account_form: nil
     )
     |> refresh()}
  end

  def handle_event("new_account", _, socket) do
    {:noreply,
     assign(socket,
       account_form:
         to_form(%{"adults" => "0", "infants" => "0", "children" => "0"}, as: :account),
       editing_account_id: nil,
       payer_guest_search: "",
       payer_guest_suggestions: []
     )}
  end

  def handle_event("edit_account", %{"id" => id}, socket) do
    payer = Billing.get_account!(socket.assigns.booking.id, id)

    attrs =
      Map.new(
        [:name, :adults, :infants, :children, :check_in_date, :check_out_date],
        &{to_string(&1), Map.fetch!(payer, &1)}
      )

    attrs = Map.merge(Billing.customer(payer).data, attrs)

    {:noreply,
     assign(socket,
       account_form: to_form(attrs, as: :account),
       editing_account_id: id,
       payer_guest_search: "",
       payer_guest_suggestions: []
     )}
  end

  def handle_event("search_payer_guest", %{"value" => query}, socket) do
    {:noreply,
     assign(socket,
       payer_guest_search: query,
       payer_guest_suggestions: Guests.search_guests(query)
     )}
  end

  def handle_event("dismiss_payer_guests", _, socket),
    do: {:noreply, assign(socket, payer_guest_search: "", payer_guest_suggestions: [])}

  def handle_event("select_payer_guest", %{"id" => id}, socket) do
    guest = Guests.get_guest!(id)

    attrs =
      Map.merge(socket.assigns.account_form.params, %{
        "name" => guest.name,
        "email" => guest.email || ""
      })

    {:noreply,
     assign(socket,
       account_form: to_form(attrs, as: :account),
       payer_guest_search: "",
       payer_guest_suggestions: []
     )}
  end

  def handle_event("validate_account", %{"account" => attrs}, socket),
    do: {:noreply, assign(socket, account_form: to_form(attrs, as: :account))}

  def handle_event("cancel_account", _, socket), do: {:noreply, assign(socket, account_form: nil)}

  def handle_event("save_account", %{"account" => attrs} = params, socket) do
    case Billing.save_account(socket.assigns.booking.id, attrs, socket.assigns.editing_account_id) do
      {:ok, payer} ->
        next? = params["next"] == "true"

        socket =
          socket
          |> assign(
            billing_scope: payer,
            buyer_form: to_form(Billing.customer(payer).data, as: :buyer),
            item_rows: nil,
            items_dirty?: false,
            preview: nil,
            pricing: nil,
            editing_account_id: nil,
            payer_guest_search: "",
            payer_guest_suggestions: [],
            account_form:
              if(next?,
                do: to_form(%{"adults" => "0", "infants" => "0", "children" => "0"}, as: :account)
              )
          )
          |> refresh()

        {:noreply,
         put_flash(socket, :info, "Plátce uložen. Doklady vystavte po kontrole náhledu.")}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(account_form: to_form(attrs, as: :account))
         |> put_flash(:error, Helpers.error(error))}
    end
  end

  def handle_event("delete_account", %{"id" => id}, socket) do
    case Billing.delete_account(socket.assigns.booking.id, id) do
      {:ok, _} ->
        payer = Billing.account(socket.assigns.booking.id)

        {:noreply,
         socket
         |> assign(
           billing_scope: payer,
           buyer_form: to_form(Billing.customer(payer).data, as: :buyer),
           item_rows: nil,
           items_dirty?: false,
           preview: nil,
           pricing: nil
         )
         |> refresh()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Helpers.error(error))}
    end
  end

  def handle_event("complete_allocation", _, socket),
    do:
      result(
        Billing.complete_allocation(
          socket.assigns.booking.id,
          is_nil(socket.assigns.booking.allocation_completed_at)
        ),
        socket
      )

  def handle_event("search_payers", %{"search" => search}, socket),
    do: {:noreply, assign(socket, :payer_search, search)}

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :value, :integer, default: nil

  defp payer_indicator(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1" role="img" title={@label} aria-label={@label}>
      <span aria-hidden="true"><.icon name={@icon} class="size-4" /></span>
      <span :if={!is_nil(@value)} aria-hidden="true">{@value}</span>
    </span>
    """
  end

  defp payer_tab_state(%{payment_state: state}) when state in ["paid", "overpaid"], do: "paid"
  defp payer_tab_state(%{state: "final"}), do: "final"
  defp payer_tab_state(%{advance_count: count}) when count > 0, do: "advance"
  defp payer_tab_state(_), do: "no_document"

  defp payer_tab_class(summary) do
    case payer_tab_state(summary) do
      "paid" -> "bg-emerald-50 text-emerald-800"
      "final" -> "bg-blue-50 text-blue-800"
      "advance" -> "bg-amber-50 text-amber-800"
      "no_document" -> "bg-slate-100 text-slate-700"
    end
  end

  defp payer_tab_label(%{payment_state: "overpaid"}), do: "Zaplaceno · přeplatek"
  defp payer_tab_label(%{payment_state: "paid"}), do: "Zaplaceno"
  defp payer_tab_label(%{state: "final"}), do: "Konečná faktura"
  defp payer_tab_label(%{state: "personal"}), do: "Soukromý pobyt"

  defp payer_tab_label(%{advance_count: count, advance_percent: percent}) when count > 0 do
    if percent, do: "Záloha #{Presentation.number(percent)} %", else: "Záloha · % neznámé"
  end

  defp payer_tab_label(_), do: "Bez dokladu"

  defp document_icon("personal"), do: "hero-home"
  defp document_icon("no_document"), do: "hero-document"
  defp document_icon("advance_issued"), do: "hero-document-arrow-up"
  defp document_icon("advance_received"), do: "hero-document-check"
  defp document_icon("advance_returned"), do: "hero-arrow-uturn-left"
  defp document_icon("final"), do: "hero-document-text"

  defp payment_icon(nil), do: "hero-minus-circle"
  defp payment_icon("unpaid"), do: "hero-clock"
  defp payment_icon("partial"), do: "hero-ellipsis-horizontal-circle"
  defp payment_icon("paid"), do: "hero-check-circle"
  defp payment_icon("overpaid"), do: "hero-arrow-up-circle"

  defp allocation(accounts, field), do: Enum.sum(Enum.map(accounts, &Map.fetch!(&1, field)))

  defp allocated_count(accounts),
    do: Enum.sum(Enum.map([:adults, :infants, :children], &allocation(accounts, &1)))

  defp visible_accounts(accounts, search),
    do:
      Enum.filter(accounts, &String.contains?(String.downcase(&1.name), String.downcase(search)))

  defp result({:ok, _}, socket),
    do: {:noreply, socket |> refresh() |> put_flash(:info, "Uloženo")}

  defp result({:error, error}, socket),
    do: {:noreply, put_flash(socket, :error, Helpers.error(error))}

  defp refresh(socket) do
    id = socket.assigns.billing_scope

    calculation = Billing.calculation(id)
    documents = Billing.list_documents(%{"billing_account_id" => id.id})

    socket =
      assign(socket,
        booking: Bookings.get_booking!(id.booking_id),
        billing_scope: Billing.account(id),
        accounts: Billing.list_accounts(id.booking_id),
        account_summaries: CozyCheckout.Billing.BookingSummary.for_accounts(id.booking_id),
        group_summary:
          CozyCheckout.Billing.BookingSummary.for_bookings([id.booking_id])[id.booking_id],
        personal?: match?(%{state: "personal"}, calculation),
        calculation: calculation,
        pricing_hint: Billing.pricing_preview(id),
        documents: documents,
        manual_delivery_summaries: Billing.manual_delivery_summaries(documents),
        abra_transfers: CozyCheckout.Abra.Transfers.for_documents(documents),
        payments: Billing.list_payments(id),
        bank_suggestions:
          CozyCheckout.Abra.Bank.for_booking(id.booking_id)
          |> Enum.filter(&(&1.document && &1.document.billing_account_id == id.id)),
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
            attrs =
              if recreation_fee?(row.changeset) and attrs["quantity"] == "",
                do: Map.put(attrs, "quantity", "0"),
                else: attrs

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

  defp recreation_fee?(changeset) do
    Ecto.Changeset.get_field(changeset, :name) == "Rekreační poplatek" and
      Ecto.Changeset.get_field(changeset, :item_type) == "extra"
  end

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
      content_class="mx-auto w-full max-w-7xl space-y-3"
      main_class="px-4 py-6 sm:px-6 lg:px-8 lg:py-8"
    >
      <div id="billing-workspace" class="min-w-0 space-y-3">
        <div class="flex justify-between flex-wrap gap-3">
          <h1 class="text-3xl font-bold">Fakturace pobytu – {@booking.guest.name}</h1><.link
            navigate={~p"/admin/bookings/#{@booking.id}"}
            class="btn"
          >Zpět na rezervaci</.link>
        </div>
        <div class="flex flex-wrap items-center justify-between gap-2 text-sm">
          <p class="text-primary-400">
            {Presentation.date(@booking.check_in_date)} – {if @booking.check_out_date,
              do: Presentation.date(@booking.check_out_date),
              else: "Odjezd není vyplněný"}
          </p>
          <nav class="flex flex-wrap items-center gap-x-5 gap-y-2 text-sm">
            <button class="link" phx-click="refresh">Obnovit přehled</button>
          </nav>
        </div>
        <section
          id="billing-calculation"
          class="min-w-0 rounded-xl border border-secondary-200 bg-white p-3 space-y-3 sm:p-4"
        >
          <details
            id="billing-accounts"
            phx-mounted={JS.ignore_attributes("open")}
            class="rounded-lg border border-secondary-200 bg-secondary-50 px-3 py-2"
          >
            <summary class="cursor-pointer text-sm">
              <span class="font-semibold">Rozdělení rezervace · </span>
              <span id="allocation-summary" class="text-sm font-normal" aria-live="polite">
                Rozděleno {allocated_count(@accounts)}/{Bookings.people_count(@booking)} osob · {@group_summary.account_count -
                  @group_summary.final_count} plátci čekají na fakturu · {@group_summary.paid_count}/{@group_summary.final_count} faktur uhrazeno
              </span>
            </summary>
            <div class="mt-3 space-y-2">
              <div class="text-sm">
                <p
                  :for={
                    {label, field} <- [
                      {"Dospělí", :adults},
                      {"Děti do 2 let", :infants},
                      {"Děti do 12 let", :children}
                    ]
                  }
                  class={
                    if allocation(@accounts, field) != Map.fetch!(@booking, field),
                      do: "text-warning font-semibold"
                  }
                >
                  {label}: {allocation(@accounts, field)}/{Map.fetch!(@booking, field)}
                </p>
                <p :if={@booking.unclassified_guests > 0} class="text-warning">
                  {@booking.unclassified_guests} historických osob čeká na zařazení.
                </p>
                <p>
                  Rozdíl v osobách neblokuje vystavení. Přeplatek jednoho plátce nehradí dluh jiného.
                </p>
              </div>
              <p class="text-sm">
                Při rozdělení upravte výchozího plátce na první rodinu a její počty. Ostatní rodiny přidejte samostatně.
              </p>
              <div class="flex flex-wrap gap-2">
                <button
                  :if={length(@accounts) > 1 || @documents == []}
                  type="button"
                  class="btn btn-primary"
                  phx-click="new_account"
                >{if length(@accounts) == 1,
                  do: "Rozdělit mezi více plátců",
                  else: "Přidat plátce"}</button>
                <button type="button" class="btn" phx-click="complete_allocation">{if @booking.allocation_completed_at,
                  do: "Znovu otevřít rozdělení",
                  else: "Potvrdit rozdělení"}</button>
              </div>
            </div>
          </details>
          <form :if={length(@accounts) > 30} phx-change="search_payers">
            <.input name="search" value={@payer_search} label="Vyhledat plátce" type="search" />
          </form>
          <nav aria-label="Plátci rezervace" class="overflow-x-auto">
            <div class="flex min-w-max items-stretch border-b border-base-300">
              <button
                :for={payer <- visible_accounts(@accounts, @payer_search)}
                id={"payer-tab-#{payer.id}"}
                type="button"
                phx-click="select_account"
                phx-value-id={payer.id}
                data-confirm={
                  if @items_dirty?,
                    do: "Přepnutím plátce zahodíte neuložené změny kalkulace. Pokračovat?"
                }
                aria-pressed={to_string(payer.id == @billing_scope.id)}
                data-billing-state={payer_tab_state(@account_summaries[payer.id])}
                class={[
                  "flex min-w-40 shrink-0 flex-col gap-1 rounded-t-lg border-b-2 px-3 py-2 text-left focus-visible:outline-2 focus-visible:outline-offset-[-2px]",
                  payer_tab_class(@account_summaries[payer.id]),
                  if(payer.id == @billing_scope.id,
                    do: "border-current ring-2 ring-inset ring-current",
                    else: "border-transparent hover:brightness-95"
                  )
                ]}
              >
                <span class="font-semibold">{payer.name}</span>
                <span class="flex items-center gap-2 text-xs">
                  <.payer_indicator
                    icon="hero-user-group"
                    label={"Celkem osob: #{payer.adults + payer.children + payer.infants}"}
                    value={payer.adults + payer.children + payer.infants}
                  />
                  <.payer_indicator
                    icon="hero-user"
                    label={"Dospělí: #{payer.adults}"}
                    value={payer.adults}
                  />
                  <.payer_indicator
                    icon="hero-users"
                    label={"Děti do 12 let: #{payer.children}"}
                    value={payer.children}
                  />
                  <.payer_indicator
                    icon="hero-face-smile"
                    label={"Děti do 2 let: #{payer.infants}"}
                    value={payer.infants}
                  />
                </span>
                <span class="flex items-center gap-2 text-xs font-semibold">
                  <.payer_indicator
                    icon={document_icon(@account_summaries[payer.id].state)}
                    label={BookingSummary.label(@account_summaries[payer.id].state)}
                  />
                  <span>{payer_tab_label(@account_summaries[payer.id])}</span>
                  <.payer_indicator
                    icon={payment_icon(@account_summaries[payer.id].payment_state)}
                    label={BookingSummary.label(@account_summaries[payer.id].payment_state)}
                  />
                  <.payer_indicator
                    :if={@account_summaries[payer.id].overdue}
                    icon="hero-exclamation-circle"
                    label="Po splatnosti"
                  />
                </span>
              </button>
            </div>
          </nav>
          <div id="active-payer" class="flex flex-wrap items-center justify-between gap-2">
            <div class="space-y-1">
              <h2 class="text-lg font-bold">Kalkulace a doklady: {@billing_scope.name}</h2>
              <p id="active-payer-counts" class="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm">
                <span class="inline-flex items-center gap-1 font-semibold">
                  <.icon name="hero-user-group" class="size-4" />
                  {@billing_scope.adults + @billing_scope.children + @billing_scope.infants} osob
                </span>
                <span>Dospělí: {@billing_scope.adults}</span>
                <span>Děti do 12 let: {@billing_scope.children}</span>
                <span>Děti do 2 let: {@billing_scope.infants}</span>
              </p>
            </div>
            <div class="flex items-center gap-2">
              <button
                type="button"
                phx-click="edit_account"
                phx-value-id={@billing_scope.id}
                class="btn btn-sm"
              >Upravit</button>
              <button
                :if={
                  !@billing_scope.default && is_nil(@account_summaries[@billing_scope.id].final_id)
                }
                type="button"
                phx-click="delete_account"
                phx-value-id={@billing_scope.id}
                class="btn btn-sm"
                data-confirm="Odstranit rozpracovaného plátce?"
              >Odstranit</button>
            </div>
          </div>
          <.form
            :if={@account_form}
            for={@account_form}
            id="payer-form"
            phx-submit="save_account"
            phx-change="validate_account"
            class="rounded border p-4 space-y-3"
          >
            <h3 class="font-bold">
              {if @editing_account_id, do: "Upravit plátce", else: "Přidat plátce"}
            </h3>
            <div class="relative" phx-click-away="dismiss_payer_guests">
              <.input
                id="payer-guest-search"
                name="payer_guest_search"
                value={@payer_guest_search}
                label="Vyhledat hosta (volitelné)"
                placeholder="Zadejte alespoň 3 znaky jména nebo e-mailu"
                phx-keyup="search_payer_guest"
                phx-debounce="300"
                autocomplete="off"
                aria-controls="payer-guest-suggestions"
              />
              <div
                :if={
                  String.length(String.trim(@payer_guest_search)) >= 3 &&
                    @payer_guest_suggestions != []
                }
                id="payer-guest-suggestions"
                class="absolute z-10 max-h-60 w-full overflow-y-auto rounded-lg border border-base-300 bg-base-100 shadow-lg"
              >
                <button
                  :for={guest <- @payer_guest_suggestions}
                  type="button"
                  phx-click="select_payer_guest"
                  phx-value-id={guest.id}
                  class="flex w-full flex-col px-4 py-3 text-left hover:bg-base-200 focus-visible:bg-base-200"
                >
                  <span class="font-medium">{guest.name}</span>
                  <span :if={guest.email} class="text-sm opacity-70">{guest.email}</span>
                </button>
              </div>
            </div>
            <p
              :if={
                String.length(String.trim(@payer_guest_search)) >= 3 && @payer_guest_suggestions == []
              }
              class="text-sm"
            >
              Žádný host nenalezen. Údaje plátce můžete vyplnit ručně.
            </p>
            <.input field={@account_form[:name]} label="Jméno / název" required />
            <div class="grid grid-cols-3 gap-3">
              <.input field={@account_form[:adults]} label="Dospělí" type="number" min="0" required />
              <.input
                field={@account_form[:infants]}
                label="Děti do 2 let"
                type="number"
                min="0"
                required
              />
              <.input
                field={@account_form[:children]}
                label="Děti do 12 let"
                type="number"
                min="0"
                required
              />
            </div>
            <.input field={@account_form[:email]} label="E-mail (volitelný)" type="email" />
            <details id="billing-account-details" phx-mounted={JS.ignore_attributes("open")}>
              <summary class="cursor-pointer py-2">Fakturační údaje a výjimka termínu</summary>
              <.input
                :for={{field, label} <- @buyer_fields -- [{"email", "Fakturační e-mail"}]}
                field={@account_form[field]}
                label={label}
              />
              <.input
                field={@account_form[:check_in_date]}
                label="Vlastní příjezd (jinak termín rezervace)"
                type="date"
              />
              <.input field={@account_form[:check_out_date]} label="Vlastní odjezd" type="date" />
              <p>
                Ceny se převezmou z uložených předvoleb skupiny. Služby a poplatky doplňte v kalkulaci konkrétního plátce.
              </p>
            </details>
            <button type="submit" class="btn btn-primary">Uložit</button>
            <button type="submit" name="next" value="true" class="btn">Uložit a přidat dalšího</button>
            <button type="button" phx-click="cancel_account" class="btn">Zrušit</button>
          </.form>
          <p
            :if={
              (@billing_scope.check_in_date && @billing_scope.check_in_date != @booking.check_in_date) ||
                (@billing_scope.check_out_date &&
                   @billing_scope.check_out_date != @booking.check_out_date)
            }
            class="alert alert-warning"
          >
            Plátce má vlastní termín: {Presentation.date(
              @billing_scope.check_in_date || @booking.check_in_date
            )} – {Presentation.date(@billing_scope.check_out_date || @booking.check_out_date)}. Zkontrolujte počet nocí v kalkulaci.
          </p>
          <p
            :if={@personal?}
            id="billing-personal"
            class={["rounded-xl bg-secondary-50 px-3 py-2 font-semibold"]}
          >
            Soukromý pobyt · bez finanční evidence
          </p>
          <button :if={!@calculation} class="btn btn-primary" phx-click="create">Založit kalkulaci</button>
          <div :if={@calculation} class="space-y-2">
            <p :if={@calculation.pricing_basis == "legacy_net"} class="alert alert-warning">
              Původní interní podklad: ceny jsou bez DPH. Číslo {@calculation.invoice_number ||
                "nepřiděleno"}, stav {@calculation.state}. Nejde o nově vystavený doklad ani potvrzení platby.
            </p>
            <p :if={@calculation.pricing_basis == "gross"} class="text-xs text-primary-400">
              Ceny včetně DPH · Naceněno pro příjezd {Presentation.date(@calculation.priced_on)} · Změny neovlivňují již vystavené doklady.
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
            <details
              id="calculation-options"
              phx-mounted={JS.ignore_attributes("open")}
              class="text-sm"
            >
              <summary class="cursor-pointer text-primary-400">
                Možnosti kalkulace a přecenění
              </summary>
              <div class="flex flex-wrap gap-2">
                <button class="btn btn-sm" phx-click="pricing" disabled={@items_dirty?}>Použít aktuální ceník – náhled</button><button
                  :if={@documents == []}
                  class="btn btn-sm"
                  phx-click="personal"
                  disabled={@items_dirty?}
                >{if @calculation.state == "personal",
                  do: "Zrušit soukromý pobyt",
                  else: "Označit soukromý pobyt"}</button>
              </div>
            </details>
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
              class="space-y-2"
            >
              <div id="billing-items" class="space-y-2">
                <div
                  class="hidden gap-3 px-3 text-sm font-semibold text-primary-400 md:grid md:grid-cols-[minmax(140px,2fr)_80px_100px_130px_110px]"
                  aria-hidden="true"
                >
                  <span>Položka</span><span class="text-right">Počet</span><span class="text-right">Nocí / jednotek</span><span class="text-right">Cena</span><span class="text-right">Celkem</span>
                </div>
                <div
                  :for={row <- @item_rows}
                  id={"billing-item-#{row.key}"}
                  class={[
                    "rounded-lg border p-2 sm:p-3",
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
                        value={
                          if recreation_fee?(row.changeset) and
                               form[:quantity].value in [0, "0"],
                             do: "",
                             else: form[:quantity].value
                        }
                        type="number"
                        label={if recreation_fee?(row.changeset), do: "Počet osob", else: "Počet"}
                        placeholder={if recreation_fee?(row.changeset), do: "Doplňte počet osob"}
                        aria-label={"Počet – #{row.changeset.data.name || "nová položka"}"}
                        min="0"
                        required={!recreation_fee?(row.changeset)}
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
                      phx-mounted={JS.ignore_attributes("open")}
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
        <div
          :if={not @personal?}
          id="payer-financial-summary"
          class="grid gap-2 rounded-xl border border-secondary-200 bg-secondary-50 p-3 sm:grid-cols-2 xl:grid-cols-4"
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
              <details
                id="billing-customer-details"
                phx-mounted={JS.ignore_attributes("open")}
                class="md:col-span-2"
              >
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
              <p
                :if={Map.has_key?(@manual_delivery_summaries, doc.id)}
                id={"manual-delivery-status-#{doc.id}"}
                class="mt-2 text-sm text-primary-500"
              >
                Odesláno ručně · {Presentation.date(Map.get(@manual_delivery_summaries, doc.id))}
              </p>
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
              <button
                id={"billing-document-manual-#{doc.id}"}
                type="button"
                class="btn btn-sm"
                phx-click="manual-delivery"
                phx-value-id={doc.id}
              >
                Zaznamenat ruční odeslání
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
                Plátce: {row.document.snapshot["customer"]["name"]} · Cílový doklad: {row.document.number} · rozdíl {Presentation.amount(
                  row.difference
                )}
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
        <.modal
          :if={@manual_document}
          id="billing-manual-modal"
          show
          on_cancel={JS.push("close-manual-delivery")}
        >
          <h2 id="billing-manual-modal-title" class="pr-10 text-xl font-bold">
            Ruční odeslání dokladu
          </h2>
          <p class="mt-2 mb-6 text-sm text-primary-400">
            {Billing.kind_label(@manual_document.kind)} {@manual_document.number}
          </p>
          <.live_component
            module={CozyCheckoutWeb.BillingLive.ManualDeliveryComponent}
            id={"booking-manual-#{@manual_document.id}"}
            document_id={@manual_document.id}
            open_form={true}
          />
        </.modal>
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
