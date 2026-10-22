defmodule CozyCheckoutWeb.BookingLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Bookings
  alias CozyCheckout.Bookings.Booking
  alias CozyCheckout.Meals.MenuPlanning

  import CozyCheckoutWeb.FlopComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :catering_errors, %{})}
  end

  # Apply default filter to show only current and future bookings
  defp apply_default_filters(params) do
    # Only apply default if no "show_all" param and no existing filter on check_out_date
    if Map.get(params, "show_all") == "true" || has_custom_filters?(params) do
      params
    else
      # Add default filter: show_current_and_future = true
      Map.put(params, "show_current_and_future", "true")
    end
  end

  # Check if user has applied custom filters
  defp has_custom_filters?(params) do
    # If there are any filters in params, don't apply default
    Map.has_key?(params, "filters") ||
      Map.has_key?(params, "invoice_state") ||
      Map.has_key?(params, "guest_search")
  end

  @impl true
  def handle_params(params, _url, socket) do
    # Apply default filter to show only current and future bookings if no filters are set
    params_with_defaults = apply_default_filters(params)

    # Normalize params: convert indexed maps to arrays for Flop
    normalized_params = normalize_flop_params(params_with_defaults)

    socket =
      case Bookings.list_bookings_with_flop(normalized_params) do
        {:ok, {bookings, meta}} ->
          # Add rooms and invoice to each booking
          bookings_with_rooms =
            Enum.map(bookings, fn booking ->
              rooms = Bookings.list_booking_rooms(booking.id)
              invoice = Bookings.get_invoice_by_booking_id(booking.id)

              booking
              |> Map.put(:rooms_list, rooms)
              |> Map.put(:invoice, invoice)
            end)

          socket
          |> assign(:bookings, bookings_with_rooms)
          |> assign(:menu_variants, MenuPlanning.list_variants())
          |> assign(
            :booking_menus,
            MenuPlanning.booking_menu_summaries(Enum.map(bookings, & &1.id))
          )
          |> assign(:meta, meta)
          |> assign(:current_params, params)

        {:error, meta} ->
          socket
          |> assign(:bookings, [])
          |> assign(:menu_variants, [])
          |> assign(:booking_menus, %{})
          |> assign(:meta, meta)
          |> assign(:current_params, params)
      end

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Booking")
    |> assign(:booking, Bookings.get_booking!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Booking")
    |> assign(:booking, %Booking{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Bookings")
    |> assign(:booking, nil)
  end

  @impl true
  def handle_info({CozyCheckoutWeb.BookingLive.FormComponent, {:saved, _booking}}, socket) do
    # Re-fetch bookings to show updated data, preserving current filters
    {:noreply,
     push_patch(socket,
       to: build_path_with_params(~p"/admin/bookings", socket.assigns.current_params)
     )}
  end

  @impl true
  def handle_info({:guest_created, guest}, socket) do
    # Forward the message to the FormComponent
    send_update(CozyCheckoutWeb.BookingLive.FormComponent,
      id: socket.assigns.booking.id || :new,
      guest_created: guest
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "update_catering",
        %{"id" => id, "inline" => attrs, "_target" => ["inline", field]},
        socket
      )
      when field in ["meal_plan", "meal_adults", "meal_children"] do
    booking = Bookings.get_booking!(id)

    attrs = Map.take(attrs, [field])

    attrs =
      if field == "meal_plan" and attrs[field] in ["half_board", "full_board"] do
        attrs
        |> Map.put("first_meal", booking.first_meal || "dinner")
        |> Map.put("last_meal", booking.last_meal || "breakfast")
      else
        attrs
      end

    result =
      if booking.status == "cancelled",
        do: {:error, :cancelled},
        else: Bookings.update_booking(booking, attrs)

    catering_result(socket, id, result)
  end

  def handle_event(
        "assign_menu",
        %{"id" => id, "selection" => %{"variant_id" => variant_id}},
        socket
      ) do
    result =
      case Ecto.UUID.cast(variant_id) do
        {:ok, variant_id} -> MenuPlanning.assign_variant(id, variant_id)
        :error -> {:error, :variant_unavailable}
      end

    catering_result(socket, id, result)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    booking = Bookings.get_booking!(id)
    {:ok, _} = Bookings.delete_booking(booking)

    # Re-fetch bookings after delete, preserving current filters
    {:noreply,
     push_patch(socket,
       to: build_path_with_params(~p"/admin/bookings", socket.assigns.current_params)
     )}
  end

  @impl true
  def handle_event("update_booking_status", %{"id" => id, "status" => status}, socket) do
    booking = Bookings.get_booking!(id)

    case Bookings.update_booking(booking, %{status: status}) do
      {:ok, _booking} ->
        {:noreply,
         socket
         |> put_flash(:info, "Booking status updated successfully")
         |> push_patch(
           to: build_path_with_params(~p"/admin/bookings", socket.assigns.current_params)
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update booking status")}
    end
  end

  @impl true
  def handle_event("update_invoice_status", %{"id" => id, "state" => state}, socket) do
    invoice = Bookings.get_booking_invoice!(id)

    case Bookings.update_invoice_state(invoice, state) do
      {:ok, _invoice} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invoice status updated successfully")
         |> push_patch(
           to: build_path_with_params(~p"/admin/bookings", socket.assigns.current_params)
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update invoice status")}
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    # Preserve show_all parameter when filtering
    filter_params = build_filter_params(params, socket.assigns.current_params)
    {:noreply, push_patch(socket, to: ~p"/admin/bookings?#{filter_params}")}
  end

  # Helper to build filter params from form
  defp build_filter_params(params, current_params) do
    filters =
      case params["filters"] do
        nil ->
          []

        filters_map ->
          filters_map
          |> Enum.map(fn {_idx, filter} ->
            # Only include filters with non-empty values
            if filter["value"] && filter["value"] != "" do
              %{
                "field" => filter["field"],
                "op" => filter["op"] || "==",
                "value" => filter["value"]
              }
            else
              nil
            end
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.with_index()
          |> Enum.into(%{}, fn {filter, idx} ->
            {to_string(idx), filter}
          end)
      end

    # Preserve existing params including custom filters
    result =
      %{
        "filters" => filters,
        "page" => params["page"],
        "page_size" => params["page_size"],
        "invoice_state" => params["invoice_state"],
        "guest_search" => params["guest_search"]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) || v == %{} || v == "" end)
      |> Map.new()

    # Preserve show_all from current params if it exists
    if Map.get(current_params, "show_all") == "true" do
      Map.put(result, "show_all", "true")
    else
      result
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      show_header={false}
      main_class="px-4 py-6 sm:px-6"
      content_class="w-full"
    >
      <div id="bookings-page" class="mx-auto w-full">
        <div class="mb-6 flex flex-wrap items-center justify-between gap-4">
          <div>
            <.link
              navigate={~p"/admin"}
              class="text-tertiary-600 hover:text-tertiary-800 mb-2 inline-block"
            >
              ← Back to Dashboard
            </.link>
            <h1 class="text-4xl font-bold text-primary-500">{@page_title}</h1>
          </div>
          <div class="flex flex-wrap gap-2">
            <.link navigate={~p"/admin/bookings/calendar"}>
              <.button>
                <.icon name="hero-calendar" class="w-5 h-5 mr-2" /> Calendar
              </.button>
            </.link>
            <.link navigate={~p"/admin/bookings/timeline"}>
              <.button>
                <.icon name="hero-bars-3" class="w-5 h-5 mr-2" /> Timeline
              </.button>
            </.link>
            <.link patch={build_path_with_params(~p"/admin/bookings/new", @current_params)}>
              <.button>
                <.icon name="hero-plus" class="w-5 h-5 mr-2" /> New Booking
              </.button>
            </.link>
          </div>
        </div>

        <div class="bg-white shadow-lg rounded-lg">
          <!-- Filter Form -->
          <.filter_form meta={@meta} path={~p"/admin/bookings"} id="bookings-filter">
            <:filter>
              <.input
                type="select"
                name="invoice_state"
                label="Invoice State"
                options={[
                  {"All", ""},
                  {"No Invoice", "no_invoice"},
                  {"Draft", "draft"},
                  {"Personal", "personal"},
                  {"Generated", "generated"},
                  {"Sent", "sent"},
                  {"Advance Paid (50%)", "advance_paid"},
                  {"Paid", "paid"}
                ]}
                value={Map.get(@meta.params, "invoice_state", "")}
              />
            </:filter>
            <:filter>
              <.input
                type="text"
                name="guest_search"
                label="Guest Name/Email"
                placeholder="Search by name or email"
                value={Map.get(@meta.params, "guest_search", "")}
              />
            </:filter>
            <:filter>
              <input type="hidden" name="filters[0][field]" value="status" />
              <input type="hidden" name="filters[0][op]" value="==" />
              <.input
                type="select"
                name="filters[0][value]"
                label="Status"
                options={[
                  {"All", ""},
                  {"Upcoming", "upcoming"},
                  {"Active", "active"},
                  {"Completed", "completed"},
                  {"Cancelled", "cancelled"}
                ]}
                value={get_filter_value(@meta, :status)}
              />
            </:filter>
            <:filter>
              <input type="hidden" name="filters[1][field]" value="check_in_date" />
              <input type="hidden" name="filters[1][op]" value=">=" />
              <.input
                type="date"
                name="filters[1][value]"
                label="Check-in From"
                value={get_filter_value(@meta, :check_in_date)}
              />
            </:filter>
            <:filter>
              <input type="hidden" name="filters[2][field]" value="check_in_date" />
              <input type="hidden" name="filters[2][op]" value="<=" />
              <.input
                type="date"
                name="filters[2][value]"
                label="Check-in To"
                value={get_filter_value(@meta, :check_in_date)}
              />
            </:filter>
            <:filter>
              <input type="hidden" name="filters[3][field]" value="short_note" />
              <input type="hidden" name="filters[3][op]" value="==" />
              <.input
                type="text"
                name="filters[3][value]"
                label="Group/Tag"
                placeholder="Filter by short note"
                value={get_filter_value(@meta, :short_note)}
              />
            </:filter>
          </.filter_form>

          <!-- View toggle -->
          <div class="px-4 py-3 bg-secondary-50 border-t border-secondary-200 flex flex-wrap items-center justify-between gap-2">
            <div class="flex flex-wrap items-center gap-2">
              <%= if Map.get(@current_params, "show_all") == "true" do %>
                <span class="text-sm text-primary-500">
                  <.icon name="hero-eye" class="w-4 h-4 inline-block" />
                  Showing all bookings (including past)
                </span>
                <.link
                  navigate={~p"/admin/bookings"}
                  class="text-sm text-tertiary-600 hover:text-tertiary-800 underline"
                >
                  Show only current & future
                </.link>
              <% else %>
                <span class="text-sm text-primary-500">
                  <.icon name="hero-eye" class="w-4 h-4 inline-block" />
                  Showing current and future bookings
                </span>
                <.link
                  navigate={~p"/admin/bookings?show_all=true"}
                  class="text-sm text-tertiary-600 hover:text-tertiary-800 underline"
                >
                  Show all bookings
                </.link>
              <% end %>
            </div>
          </div>

          <!-- Fixed desktop columns and stacked cards on narrow screens. -->
          <div id="bookings-table-container" class="px-3 pb-2 lg:px-0">
            <table
              id="bookings-table"
              class="w-full lg:table-fixed [&_.fieldset]:mb-0 [&_.fieldset]:p-0 [&_.fieldset]:gap-0 [&_.label]:text-xs [&_.label]:mb-1"
            >
              <colgroup class="hidden lg:table-column-group">
                <col class="w-[28%]" />
                <col class="w-[148px]" />
                <col />
                <col class="w-[136px]" />
                <col class="w-[180px]" />
                <col class="w-[100px]" />
              </colgroup>
              <thead class="hidden bg-secondary-50 lg:table-header-group">
                <tr class="text-left text-xs font-semibold text-primary-400">
                  <th class="px-3 py-3">
                    <span>Rezervace a pobyt</span>
                    <div class="mt-1 flex flex-wrap gap-x-3 gap-y-1 font-normal">
                      <.link
                        id="bookings-sort-arrival"
                        patch={
                          build_path(
                            ~p"/admin/bookings",
                            @meta,
                            :order,
                            :check_in_date,
                            @current_params
                          )
                        }
                        class="inline-flex items-center gap-1 hover:text-tertiary-600"
                      >
                        Příjezd <.sort_icon meta={@meta} field={:check_in_date} />
                      </.link>
                      <.link
                        id="bookings-sort-departure"
                        patch={
                          build_path(
                            ~p"/admin/bookings",
                            @meta,
                            :order,
                            :check_out_date,
                            @current_params
                          )
                        }
                        class="inline-flex items-center gap-1 hover:text-tertiary-600"
                      >
                        Odjezd <.sort_icon meta={@meta} field={:check_out_date} />
                      </.link>
                    </div>
                  </th>
                  <th class="px-2 py-3">Stravování</th>
                  <th class="px-2 py-3">Menu</th>
                  <th class="px-2 py-3">Osoby</th>
                  <.sortable_header
                    meta={@meta}
                    field={:status}
                    path={~p"/admin/bookings"}
                    raw_params={@current_params}
                    class="!px-2 !tracking-normal !normal-case"
                  >
                    Stav / faktura
                  </.sortable_header>
                  <th class="px-2 py-3 text-right">Akce</th>
                </tr>
              </thead>
              <tbody class="grid gap-3 bg-white lg:table-row-group lg:divide-y lg:divide-secondary-200">
                <%= if @bookings == [] do %>
                  <tr>
                    <td colspan="6" class="px-6 py-12 text-center text-primary-400">
                      No bookings found.
                    </td>
                  </tr>
                <% else %>
                  <tr
                    :for={booking <- @bookings}
                    id={"booking-row-#{booking.id}"}
                    class="grid min-w-0 grid-cols-2 gap-x-3 rounded-lg border border-secondary-200 p-3 hover:bg-secondary-50 lg:table-row lg:rounded-none lg:border-0 lg:p-0"
                  >
                    <td class="col-span-2 min-w-0 px-0 py-2 align-top text-sm text-primary-500 lg:px-3 lg:py-3">
                      <.link
                        navigate={
                          build_path_with_params(~p"/admin/bookings/#{booking}", @current_params)
                        }
                        title={booking.guest.name}
                        class="block truncate font-semibold text-tertiary-700 hover:underline"
                      >
                        {booking.guest.name}
                      </.link>
                      <span
                        :if={booking.short_note}
                        class="mt-1 inline-block max-w-full truncate rounded bg-info-light px-1.5 text-xs text-tertiary-800"
                        title={booking.short_note}
                      >
                        {booking.short_note}
                      </span>
                      <div
                        id={"booking-stay-#{booking.id}"}
                        class="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-primary-400"
                      >
                        <span class="inline-flex items-center gap-1">
                          <.icon name="hero-calendar-days" class="size-3.5 shrink-0" />
                          <time datetime={booking.check_in_date}>{Calendar.strftime(
                            booking.check_in_date,
                            "%d.%m.%Y"
                          )}</time>
                          <span>–</span>
                          <time :if={booking.check_out_date} datetime={booking.check_out_date}>{Calendar.strftime(
                            booking.check_out_date,
                            "%d.%m.%Y"
                          )}</time>
                          <span :if={is_nil(booking.check_out_date)}>odjezd nevyplněn</span>
                        </span>
                        <span
                          :if={booking.check_out_date}
                          title="Počet nocí"
                          class="inline-flex items-center gap-1"
                        >
                          <.icon name="hero-moon" class="size-3.5 shrink-0" />
                          {Date.diff(booking.check_out_date, booking.check_in_date)} nocí
                        </span>
                      </div>
                      <div
                        :if={booking.rooms_list != []}
                        id={"booking-rooms-#{booking.id}"}
                        class="mt-1 flex min-w-0 items-center gap-1 text-xs text-primary-400"
                        title={"Pokoje: " <> Enum.map_join(booking.rooms_list, ", ", & &1.room_number)}
                      >
                        <.icon name="hero-key" class="size-3.5 shrink-0" />
                        <span class="truncate">Pokoj: {Enum.map_join(
                          booking.rooms_list,
                          ", ",
                          & &1.room_number
                        )}</span>
                      </div>
                    </td>
                    <.catering_cells
                      booking={booking}
                      variants={@menu_variants}
                      menu={@booking_menus[booking.id]}
                      error={@catering_errors[booking.id]}
                    />
                    <td class="min-w-0 py-2 align-top lg:px-2 lg:py-3">
                      <div class="mb-1 text-xs font-medium text-primary-400 lg:hidden">
                        Stav / faktura
                      </div>
                      <div class="space-y-2">
                        <div
                          class="relative"
                          id={"booking-status-#{booking.id}"}
                          phx-click-away={JS.hide(to: "#status-menu-#{booking.id}")}
                        >
                          <button
                            type="button"
                            phx-click={JS.toggle(to: "#status-menu-#{booking.id}")}
                            class="w-full min-w-0 text-left inline-flex items-center justify-between gap-1 hover:opacity-80 transition-opacity"
                            title={"Stav rezervace: " <> String.capitalize(booking.status)}
                            aria-label="Změnit stav rezervace"
                          >
                            <.icon name="hero-bookmark" class="size-3.5 shrink-0 text-primary-400" />
                            <span class={[
                              "min-w-0 truncate px-2 text-xs leading-5 font-semibold rounded-full",
                              status_badge_class(booking.status)
                            ]}>
                              {String.capitalize(booking.status)}
                            </span>
                            <.icon name="hero-chevron-down" class="w-3 h-3 text-primary-400" />
                          </button>

                          <div
                            id={"status-menu-#{booking.id}"}
                            class="hidden absolute right-0 z-10 mt-1 w-40 rounded-md shadow-lg bg-white ring-1 ring-black ring-opacity-5"
                          >
                            <div class="py-1" role="menu">
                              <button
                                type="button"
                                phx-click={
                                  JS.push("update_booking_status")
                                  |> JS.hide(to: "#status-menu-#{booking.id}")
                                }
                                phx-value-id={booking.id}
                                phx-value-status="upcoming"
                                class="block w-full text-left px-4 py-2 text-sm hover:bg-secondary-50 transition-colors"
                              >
                                <span class={[
                                  "min-w-0 truncate px-2 text-xs leading-5 font-semibold rounded-full",
                                  status_badge_class("upcoming")
                                ]}>
                                  Upcoming
                                </span>
                              </button>
                              <button
                                type="button"
                                phx-click={
                                  JS.push("update_booking_status")
                                  |> JS.hide(to: "#status-menu-#{booking.id}")
                                }
                                phx-value-id={booking.id}
                                phx-value-status="active"
                                class="block w-full text-left px-4 py-2 text-sm hover:bg-secondary-50 transition-colors"
                              >
                                <span class={[
                                  "min-w-0 truncate px-2 text-xs leading-5 font-semibold rounded-full",
                                  status_badge_class("active")
                                ]}>
                                  Active
                                </span>
                              </button>
                              <button
                                type="button"
                                phx-click={
                                  JS.push("update_booking_status")
                                  |> JS.hide(to: "#status-menu-#{booking.id}")
                                }
                                phx-value-id={booking.id}
                                phx-value-status="completed"
                                class="block w-full text-left px-4 py-2 text-sm hover:bg-secondary-50 transition-colors"
                              >
                                <span class={[
                                  "min-w-0 truncate px-2 text-xs leading-5 font-semibold rounded-full",
                                  status_badge_class("completed")
                                ]}>
                                  Completed
                                </span>
                              </button>
                              <button
                                type="button"
                                phx-click={
                                  JS.push("update_booking_status")
                                  |> JS.hide(to: "#status-menu-#{booking.id}")
                                }
                                phx-value-id={booking.id}
                                phx-value-status="cancelled"
                                class="block w-full text-left px-4 py-2 text-sm hover:bg-secondary-50 transition-colors"
                              >
                                <span class={[
                                  "min-w-0 truncate px-2 text-xs leading-5 font-semibold rounded-full",
                                  status_badge_class("cancelled")
                                ]}>
                                  Cancelled
                                </span>
                              </button>
                            </div>
                          </div>
                        </div>

                        <%= if Map.get(booking, :invoice) do %>
                          <div
                            class="relative"
                            id={"invoice-status-#{booking.id}"}
                            phx-click-away={JS.hide(to: "#invoice-menu-#{booking.id}")}
                          >
                            <button
                              type="button"
                              phx-click={JS.toggle(to: "#invoice-menu-#{booking.id}")}
                              class="w-full min-w-0 text-left inline-flex items-center justify-between gap-1 hover:opacity-80 transition-opacity"
                              title={"Stav faktury: " <> invoice_state_label(booking.invoice.state)}
                              aria-label="Změnit stav faktury"
                            >
                              <.icon
                                name="hero-document-currency-dollar"
                                class="size-3.5 shrink-0 text-primary-400"
                              />
                              <span class={[
                                "min-w-0 truncate px-2 text-xs leading-5 font-semibold rounded-full",
                                invoice_state_badge_class(booking.invoice.state)
                              ]}>
                                {invoice_state_label(booking.invoice.state)}
                              </span>
                              <.icon name="hero-chevron-down" class="w-3 h-3 text-primary-400" />
                            </button>

                            <div
                              id={"invoice-menu-#{booking.id}"}
                              class="hidden absolute right-0 z-10 mt-1 w-48 rounded-md shadow-lg bg-white ring-1 ring-black ring-opacity-5"
                            >
                              <div class="py-1" role="menu">
                                <button
                                  type="button"
                                  phx-click={
                                    JS.push("update_invoice_status")
                                    |> JS.hide(to: "#invoice-menu-#{booking.id}")
                                  }
                                  phx-value-id={booking.invoice.id}
                                  phx-value-state="draft"
                                  class="block w-full text-left px-4 py-2 text-sm hover:bg-secondary-50 transition-colors"
                                >
                                  <span class={[
                                    "min-w-0 truncate px-2 text-xs leading-5 font-semibold rounded-full",
                                    invoice_state_badge_class("draft")
                                  ]}>
                                    Draft
                                  </span>
                                </button>
                                <button
                                  type="button"
                                  phx-click={
                                    JS.push("update_invoice_status")
                                    |> JS.hide(to: "#invoice-menu-#{booking.id}")
                                  }
                                  phx-value-id={booking.invoice.id}
                                  phx-value-state="personal"
                                  class="block w-full text-left px-4 py-2 text-sm hover:bg-secondary-50 transition-colors"
                                >
                                  <span class={[
                                    "min-w-0 truncate px-2 text-xs leading-5 font-semibold rounded-full",
                                    invoice_state_badge_class("personal")
                                  ]}>
                                    Personal
                                  </span>
                                </button>
                                <button
                                  type="button"
                                  phx-click={
                                    JS.push("update_invoice_status")
                                    |> JS.hide(to: "#invoice-menu-#{booking.id}")
                                  }
                                  phx-value-id={booking.invoice.id}
                                  phx-value-state="generated"
                                  class="block w-full text-left px-4 py-2 text-sm hover:bg-secondary-50 transition-colors"
                                >
                                  <span class={[
                                    "min-w-0 truncate px-2 text-xs leading-5 font-semibold rounded-full",
                                    invoice_state_badge_class("generated")
                                  ]}>
                                    Generated
                                  </span>
                                </button>
                                <button
                                  type="button"
                                  phx-click={
                                    JS.push("update_invoice_status")
                                    |> JS.hide(to: "#invoice-menu-#{booking.id}")
                                  }
                                  phx-value-id={booking.invoice.id}
                                  phx-value-state="sent"
                                  class="block w-full text-left px-4 py-2 text-sm hover:bg-secondary-50 transition-colors"
                                >
                                  <span class={[
                                    "min-w-0 truncate px-2 text-xs leading-5 font-semibold rounded-full",
                                    invoice_state_badge_class("sent")
                                  ]}>
                                    Sent
                                  </span>
                                </button>
                                <button
                                  type="button"
                                  phx-click={
                                    JS.push("update_invoice_status")
                                    |> JS.hide(to: "#invoice-menu-#{booking.id}")
                                  }
                                  phx-value-id={booking.invoice.id}
                                  phx-value-state="advance_paid"
                                  class="block w-full text-left px-4 py-2 text-sm hover:bg-secondary-50 transition-colors"
                                >
                                  <span class={[
                                    "min-w-0 truncate px-2 text-xs leading-5 font-semibold rounded-full",
                                    invoice_state_badge_class("advance_paid")
                                  ]}>
                                    Advance Paid (50%)
                                  </span>
                                </button>
                                <button
                                  type="button"
                                  phx-click={
                                    JS.push("update_invoice_status")
                                    |> JS.hide(to: "#invoice-menu-#{booking.id}")
                                  }
                                  phx-value-id={booking.invoice.id}
                                  phx-value-state="paid"
                                  class="block w-full text-left px-4 py-2 text-sm hover:bg-secondary-50 transition-colors"
                                >
                                  <span class={[
                                    "min-w-0 truncate px-2 text-xs leading-5 font-semibold rounded-full",
                                    invoice_state_badge_class("paid")
                                  ]}>
                                    Paid
                                  </span>
                                </button>
                              </div>
                            </div>
                          </div>
                        <% else %>
                          <span class="text-primary-300 text-sm">—</span>
                        <% end %>
                      </div>
                    </td>
                    <td class="col-span-2 min-w-0 py-2 text-right align-top lg:px-2 lg:py-3">
                      <div class="flex justify-end gap-1">
                        <.link
                          id={"booking-view-#{booking.id}"}
                          navigate={
                            build_path_with_params(~p"/admin/bookings/#{booking}", @current_params)
                          }
                          title="Detail rezervace"
                          aria-label="Detail rezervace"
                          class="inline-flex size-7 items-center justify-center rounded text-tertiary-600 hover:bg-tertiary-100 focus-visible:outline-2"
                        >
                          <.icon name="hero-eye" class="size-4" />
                        </.link>
                        <.link
                          id={"booking-edit-#{booking.id}"}
                          patch={
                            build_path_with_params(
                              ~p"/admin/bookings/#{booking}/edit",
                              @current_params
                            )
                          }
                          title="Upravit rezervaci"
                          aria-label="Upravit rezervaci"
                          class="inline-flex size-7 items-center justify-center rounded text-tertiary-600 hover:bg-tertiary-100 focus-visible:outline-2"
                        >
                          <.icon name="hero-pencil-square" class="size-4" />
                        </.link>
                        <button
                          id={"booking-delete-#{booking.id}"}
                          type="button"
                          phx-click={JS.push("delete", value: %{id: booking.id})}
                          data-confirm="Are you sure? This will not delete associated orders."
                          title="Smazat rezervaci"
                          aria-label="Smazat rezervaci"
                          class="inline-flex size-7 items-center justify-center rounded text-error hover:bg-error-light focus-visible:outline-2"
                        >
                          <.icon name="hero-trash" class="size-4" />
                        </button>
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
          <!-- Pagination -->
          <.pagination meta={@meta} path={~p"/admin/bookings"} />
        </div>

        <.modal
          :if={@live_action in [:new, :edit]}
          id="booking-modal"
          show
          on_cancel={JS.patch(build_path_with_params(~p"/admin/bookings", @current_params))}
        >
          <.live_component
            module={CozyCheckoutWeb.BookingLive.FormComponent}
            id={@booking.id || :new}
            title={@page_title}
            action={@live_action}
            booking={@booking}
            patch={build_path_with_params(~p"/admin/bookings", @current_params)}
          />
        </.modal>
      </div>
    </Layouts.app>
    """
  end

  defp status_badge_class("upcoming"), do: "bg-tertiary-100 text-tertiary-800"
  defp status_badge_class("active"), do: "bg-success-light text-success-dark"
  defp status_badge_class("completed"), do: "bg-secondary-100 text-primary-500"
  defp status_badge_class("cancelled"), do: "bg-error-light text-error-dark"
  defp status_badge_class(_), do: "bg-secondary-100 text-primary-500"

  defp invoice_state_badge_class("draft"), do: "bg-secondary-100 text-primary-500"
  defp invoice_state_badge_class("personal"), do: "bg-warning-light text-warning-dark"
  defp invoice_state_badge_class("generated"), do: "bg-tertiary-100 text-tertiary-800"
  defp invoice_state_badge_class("sent"), do: "bg-info-light text-info-dark"
  defp invoice_state_badge_class("advance_paid"), do: "bg-warning-light text-warning-dark"
  defp invoice_state_badge_class("paid"), do: "bg-success-light text-success-dark"
  defp invoice_state_badge_class(_), do: "bg-secondary-100 text-primary-500"

  defp invoice_state_label("draft"), do: "Draft"
  defp invoice_state_label("personal"), do: "Personal"
  defp invoice_state_label("generated"), do: "Generated"
  defp invoice_state_label("sent"), do: "Sent"
  defp invoice_state_label("advance_paid"), do: "Advance Paid (50%)"
  defp invoice_state_label("paid"), do: "Paid"
  defp invoice_state_label(state), do: String.capitalize(state)

  # Convert Phoenix indexed map params (e.g., %{"0" => "value"}) to arrays for Flop
  defp normalize_flop_params(params) do
    params
    |> normalize_array_param("order_by")
    |> normalize_array_param("order_directions")
  end

  defp normalize_array_param(params, key) do
    case Map.get(params, key) do
      # If it's a map with string keys "0", "1", etc., convert to array
      value when is_map(value) ->
        array =
          value
          |> Enum.sort_by(fn {k, _v} -> String.to_integer(k) end)
          |> Enum.map(fn {_k, v} -> v end)

        Map.put(params, key, array)

      # Otherwise, leave it as is
      _ ->
        params
    end
  end

  defp catering_result(socket, id, {:ok, _}) do
    {:noreply,
     socket
     |> assign(:catering_errors, Map.delete(socket.assigns.catering_errors, id))
     |> push_patch(to: build_path_with_params(~p"/admin/bookings", socket.assigns.current_params))}
  end

  defp catering_result(socket, id, {:error, reason}) do
    message =
      case reason do
        %Ecto.Changeset{} = cs ->
          cond do
            Keyword.has_key?(cs.errors, :check_out_date) ->
              "Nejdřív doplňte datum odjezdu v detailu."

            Keyword.has_key?(cs.errors, :first_meal) or Keyword.has_key?(cs.errors, :last_meal) ->
              "Upravte první a poslední jídlo v detailu rezervace."

            true ->
              "Počet musí být celé nezáporné číslo. Prázdné pole znamená neznámý počet."
          end

        {:invalid_menu, errors} ->
          Enum.join(errors, " ")

        :cancelled ->
          "Zrušené rezervaci nelze měnit stravování."

        _ ->
          "Menu nelze přiřadit. Obnovte seznam a zkontrolujte termín a stravování."
      end

    {:noreply,
     assign(socket, :catering_errors, Map.put(socket.assigns.catering_errors, id, message))}
  end

  attr :booking, :map, required: true
  attr :variants, :list, required: true
  attr :menu, :any, default: nil
  attr :error, :string, default: nil

  defp catering_cells(assigns) do
    suitable = MenuPlanning.suitable_variants(assigns.booking, assigns.variants)
    catered = assigns.booking.meal_plan in ["half_board", "full_board"]
    stale = MenuPlanning.stale?(assigns.menu, assigns.booking)

    selected =
      if assigns.menu && not stale &&
           Enum.any?(suitable, &(&1.id == assigns.menu.menu_variant_id)),
         do: assigns.menu.menu_variant_id,
         else: ""

    assigns =
      assigns
      |> assign(:suitable, suitable)
      |> assign(:catered, catered)
      |> assign(:stale, stale)
      |> assign(:disabled, assigns.booking.status == "cancelled")
      |> assign(
        :catering_form,
        to_form(
          Map.take(assigns.booking, [:meal_plan, :meal_adults, :meal_children])
          |> Map.new(fn {k, v} -> {to_string(k), v || ""} end),
          as: :inline
        )
      )
      |> assign(:menu_form, to_form(%{"variant_id" => selected}, as: :selection))

    ~H"""
    <td class="min-w-0 py-2 align-top text-sm lg:px-2 lg:py-3">
      <div class="mb-1 text-xs font-medium text-primary-400 lg:hidden">Stravování</div>
      <div class="flex min-w-0 items-center gap-1">
        <.form
          for={@catering_form}
          id={"catering-plan-#{@booking.id}"}
          phx-change="update_catering"
          phx-value-id={@booking.id}
          class="min-w-0 flex-1"
        >
          <.input
            field={@catering_form[:meal_plan]}
            id={"catering-plan-input-#{@booking.id}"}
            type="select"
            aria-label="Stravování"
            class="h-9 w-full min-w-0 rounded-md border border-secondary-300 bg-white px-2 text-xs text-primary-500 focus:border-tertiary-500 focus:outline-none focus:ring-1 focus:ring-tertiary-500 disabled:opacity-50"
            disabled={@disabled}
            options={[
              {"Nezadáno", ""},
              {"Bez stravy", "none"},
              {"Polopenze", "half_board"},
              {"Plná penze", "full_board"}
            ]}
          />
        </.form>
        <.link
          navigate={~p"/admin/bookings/#{@booking.id}/edit"}
          title="Upravit podrobnosti stravování"
          aria-label="Upravit podrobnosti stravování"
          class="inline-flex size-6 shrink-0 items-center justify-center rounded text-tertiary-600 hover:bg-tertiary-100 focus-visible:outline-2"
        ><.icon name="hero-adjustments-horizontal" class="size-4" /></.link>
      </div>
      <p :if={@error} id={"catering-error-#{@booking.id}"} role="alert" class="mt-2 text-error">
        {@error}
      </p>
    </td>
    <td class="min-w-0 py-2 align-top text-sm lg:px-2 lg:py-3">
      <div class="mb-1 text-xs font-medium text-primary-400 lg:hidden">Menu</div>
      <div class="flex min-w-0 items-center gap-1">
        <.form
          :if={@catered}
          for={@menu_form}
          id={"catering-menu-#{@booking.id}"}
          phx-change="assign_menu"
          phx-value-id={@booking.id}
          class="min-w-0 flex-1"
        >
          <.input
            field={@menu_form[:variant_id]}
            id={"catering-menu-input-#{@booking.id}"}
            type="select"
            aria-label="Menu rezervace"
            title={if @menu, do: @menu.variant_name, else: "Vybrat vhodné menu"}
            class="h-9 w-full min-w-0 rounded-md border border-secondary-300 bg-white px-2 text-xs text-primary-500 focus:border-tertiary-500 focus:outline-none focus:ring-1 focus:ring-tertiary-500 disabled:opacity-50"
            disabled={@disabled or @suitable == []}
            prompt={if @suitable == [], do: "Žádné vhodné menu", else: "Vybrat menu"}
            options={Enum.map(@suitable, &{&1.name, &1.id})}
          />
        </.form>
        <span :if={not @catered}>—</span>
        <.link
          :if={not is_nil(@menu) and @catered}
          navigate={~p"/admin/bookings/#{@booking.id}/menu"}
          title="Zobrazit menu"
          aria-label="Zobrazit menu"
          class="inline-flex size-6 shrink-0 items-center justify-center rounded text-tertiary-600 hover:bg-tertiary-100 focus-visible:outline-2"
        ><.icon name="hero-document-text" class="size-4" /></.link>
      </div>
      <p
        :if={@catered and @stale}
        id={"catering-stale-#{@booking.id}"}
        title={"Původní menu: " <> @menu.variant_name <> ". Termín nebo stravování se změnilo; vyberte znovu vhodné menu."}
        class="mt-1 flex items-center gap-1 text-xs text-warning"
      >
        <.icon name="hero-exclamation-triangle" class="size-3.5 shrink-0" /> Vybrat znovu
      </p>
    </td>
    <td class="min-w-0 py-2 align-top text-sm lg:px-2 lg:py-3">
      <.form
        :if={@catered}
        for={@catering_form}
        id={"catering-counts-#{@booking.id}"}
        phx-change="update_catering"
        phx-value-id={@booking.id}
        class="grid min-w-0 grid-cols-2 gap-2"
      >
        <.input
          field={@catering_form[:meal_adults]}
          id={"catering-adults-#{@booking.id}"}
          type="number"
          label="Dosp."
          aria-label="Dospělí ke stravování"
          class="h-9 w-full min-w-0 rounded-md border border-secondary-300 bg-white px-1.5 text-sm text-primary-500 focus:border-tertiary-500 focus:outline-none focus:ring-1 focus:ring-tertiary-500 disabled:opacity-50"
          min="0"
          step="1"
          placeholder="?"
          phx-debounce="blur"
          disabled={@disabled}
        />
        <.input
          field={@catering_form[:meal_children]}
          id={"catering-children-#{@booking.id}"}
          type="number"
          label="Děti"
          aria-label="Děti ke stravování"
          class="h-9 w-full min-w-0 rounded-md border border-secondary-300 bg-white px-1.5 text-sm text-primary-500 focus:border-tertiary-500 focus:outline-none focus:ring-1 focus:ring-tertiary-500 disabled:opacity-50"
          min="0"
          step="1"
          placeholder="?"
          phx-debounce="blur"
          disabled={@disabled}
        />
      </.form>
      <p
        :if={@catered and (is_nil(@booking.meal_adults) or is_nil(@booking.meal_children))}
        id={"catering-missing-counts-#{@booking.id}"}
        class="mt-1 flex items-center gap-1 text-xs text-warning"
        title="Doplňte dospělé i děti včetně nul. Do té doby se porce nezapočítávají."
      >
        <.icon name="hero-exclamation-triangle" class="size-3.5 shrink-0" /> Chybí počty
      </p>
      <span :if={not @catered}>—</span>
    </td>
    """
  end
end
