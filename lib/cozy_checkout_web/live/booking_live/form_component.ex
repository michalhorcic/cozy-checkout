defmodule CozyCheckoutWeb.BookingLive.FormComponent do
  use CozyCheckoutWeb, :live_component

  alias CozyCheckout.Bookings
  alias CozyCheckout.Guests
  alias CozyCheckout.Rooms
  import CozyCheckoutWeb.MealComponents

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
      </.header>

      <.form
        for={@form}
        id="booking-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="mb-4">
          <label class="block text-sm font-semibold leading-6 text-zinc-800 mb-2">
            Guest <span class="text-rose-600">*</span>
          </label>
          <div class="relative" phx-click-away={JS.hide(to: "#guest-suggestions")}>
            <input
              type="text"
              id="guest-search"
              name="guest_search"
              value={@guest_search_text}
              placeholder="Type at least 3 characters to search..."
              phx-target={@myself}
              phx-keyup="search_guest"
              phx-debounce="300"
              autocomplete="off"
              class="mt-2 block w-full rounded-lg text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6 phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400 border-zinc-300 focus:border-zinc-400"
            />
            <input type="hidden" name="booking[guest_id]" value={@selected_guest_id} />

            <%= if @show_suggestions do %>
              <div
                id="guest-suggestions"
                class="absolute z-10 mt-1 w-full bg-white shadow-lg max-h-60 rounded-md py-1 text-base ring-1 ring-black ring-opacity-5 overflow-auto focus:outline-none sm:text-sm"
              >
                <%= if @guest_suggestions == [] and String.length(@guest_search_text) >= 3 do %>
                  <div
                    class="cursor-pointer select-none relative py-3 pl-3 pr-9 hover:bg-tertiary-600 hover:text-white transition-colors"
                    phx-click="show_create_guest_modal"
                    phx-target={@myself}
                  >
                    <div class="flex items-center">
                      <span class="font-semibold text-lg mr-2">+</span>
                      <span>Create new guest: {@guest_search_text}</span>
                    </div>
                  </div>
                <% else %>
                  <%= for guest <- @guest_suggestions do %>
                    <div
                      class="cursor-pointer select-none relative py-2 pl-3 pr-9 hover:bg-tertiary-600 hover:text-white transition-colors"
                      phx-click="select_guest"
                      phx-value-guest-id={guest.id}
                      phx-value-guest-name={guest.name}
                      phx-target={@myself}
                    >
                      <div class="flex flex-col">
                        <span class="font-medium">{guest.name}</span>
                        <%= if guest.email do %>
                          <span class="text-sm opacity-75">{guest.email}</span>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                  <%= if String.length(@guest_search_text) >= 3 do %>
                    <div
                      class="cursor-pointer select-none relative py-3 pl-3 pr-9 hover:bg-tertiary-600 hover:text-white transition-colors border-t"
                      phx-click="show_create_guest_modal"
                      phx-target={@myself}
                    >
                      <div class="flex items-center">
                        <span class="font-semibold text-lg mr-2">+</span>
                        <span>Create new guest</span>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>
            <% end %>

            <%= if @selected_guest_name do %>
              <div class="mt-2 inline-flex items-center gap-2 px-3 py-1 bg-info-light text-tertiary-800 rounded-full text-sm">
                <span>{@selected_guest_name}</span>
                <button
                  type="button"
                  phx-click="clear_guest"
                  phx-target={@myself}
                  class="hover:text-tertiary-600"
                >
                  <.icon name="hero-x-mark" class="w-4 h-4" />
                </button>
              </div>
            <% end %>

            <%= if @form[:guest_id].errors != [] do %>
              <p class="mt-2 text-sm text-rose-600">
                {translate_error(List.first(@form[:guest_id].errors))}
              </p>
            <% end %>
          </div>
        </div>

        <div class="mb-4">
          <details id="booking-room-picker">
            <summary class="cursor-pointer py-3 text-sm font-semibold">
              {if @selected_room_ids == [],
                do: "Pokoje nepřiřazeny · Vybrat",
                else:
                  "Pokoje: " <>
                    Enum.map_join(
                      Enum.filter(@rooms, &(&1.id in @selected_room_ids)),
                      ", ",
                      & &1.room_number
                    ) <> " · Upravit"}
            </summary>
            <div class="grid grid-cols-2 gap-2">
              <%= for room <- @rooms do %>
                <label class="flex items-center p-3 border rounded-lg cursor-pointer hover:bg-secondary-50 transition-colors">
                  <input
                    type="checkbox"
                    name="room_ids[]"
                    value={room.id}
                    checked={room.id in @selected_room_ids}
                    phx-target={@myself}
                    phx-click="toggle_room"
                    phx-value-room-id={room.id}
                    class="rounded border-secondary-300 text-tertiary-600 focus:ring-indigo-500"
                  />
                  <span class="ml-2 text-sm text-primary-500">
                    {room.room_number}
                    <%= if room.name do %>
                      <span class="text-primary-400">- {room.name}</span>
                    <% end %>
                    <span class="text-primary-300 text-xs block">Capacity: {room.capacity}</span>
                  </span>
                </label>
              <% end %>
            </div>
          </details>
          <%= if @room_error do %>
            <p class="mt-2 text-sm text-rose-600">{@room_error}</p>
          <% end %>
        </div>

        <fieldset id="booking-dates" class="my-4 rounded-lg border p-4">
          <legend>Termín pobytu</legend>
          <div class="grid grid-cols-2 gap-3">
            <.input field={@form[:check_in_date]} type="date" label="Příjezd" required />
            <.input field={@form[:check_out_date]} type="date" label="Odjezd" />
          </div>
          <p aria-live="polite">{nights_label(@form)}</p>
          <details>
            <summary class="cursor-pointer py-3">Vybrat rozsah v kalendáři</summary>
            <p class="text-sm">První kliknutí: příjezd, druhé: odjezd.</p>
            <div class="flex items-center justify-between my-2">
              <button
                type="button"
                phx-click="calendar_month"
                phx-value-offset="-1"
                phx-target={@myself}
                aria-label="Předchozí měsíc"
                class="btn"
              >‹</button>
              <span>{month_label(@calendar_month)}</span>
              <button
                type="button"
                phx-click="calendar_month"
                phx-value-offset="1"
                phx-target={@myself}
                aria-label="Další měsíc"
                class="btn"
              >›</button>
            </div>
            <div class="grid grid-cols-7 gap-1" role="group" aria-label="Kalendář termínu">
              <span :for={day <- ~w(Po Út St Čt Pá So Ne)} class="text-center text-xs">{day}</span>
              <span :for={_ <- calendar_padding(@calendar_month)}></span>
              <button
                :for={date <- Date.range(@calendar_month, Date.end_of_month(@calendar_month))}
                type="button"
                phx-click="calendar_day"
                phx-value-date={date}
                phx-target={@myself}
                aria-label={Calendar.strftime(date, "%d. %m. %Y")}
                aria-pressed={selected_date?(@form, date)}
                class={[
                  "min-h-11 rounded text-center",
                  if(selected_date?(@form, date),
                    do: "bg-primary text-primary-content",
                    else: "bg-base-200"
                  )
                ]}
              >{date.day}</button>
            </div>
          </details>
        </fieldset>
        <fieldset class="my-4 rounded-lg border p-4">
          <legend>Ubytovaní · společné počty rezervace</legend>
          <div class="grid grid-cols-3 gap-3">
            <.input field={@form[:adults]} type="number" label="Dospělí" min="0" required />
            <.input field={@form[:infants]} type="number" label="Děti do 2 let" min="0" required />
            <.input field={@form[:children]} type="number" label="Děti do 12 let" min="0" required />
          </div>
          <div
            :if={@form[:unclassified_guests].value not in [nil, 0, "0"]}
            class="alert alert-warning"
          >
            Historické osoby bez známé kategorie: doplňte rozpad, věk nebyl odhadnut.
            <.input
              field={@form[:unclassified_guests]}
              type="number"
              label="Nezařazené osoby"
              min="0"
            />
          </div>
        </fieldset>

        <.input
          field={@form[:status]}
          type="select"
          label="Status"
          options={[
            {"Upcoming", "upcoming"},
            {"Active", "active"},
            {"Completed", "completed"},
            {"Cancelled", "cancelled"}
          ]}
          required
        />

        <.input
          field={@form[:short_note]}
          type="text"
          label="Short Note (for grouping)"
          placeholder="e.g., Group A, Family reunion"
          maxlength="30"
        />

        <.input field={@form[:notes]} type="textarea" label="Notes" rows="3" />

        <fieldset id="booking-catering" class="my-6 rounded-lg border border-secondary-200 p-4">
          <legend class="px-2 font-semibold text-primary-500">Stravování</legend>
          <p class="mb-3 text-sm text-primary-400">
            Jeden režim pro celý pobyt. Počty strávníků jsou nezávislé na faktuře.
          </p>
          <.input
            field={@form[:meal_plan]}
            type="select"
            label="Režim stravování"
            options={meal_plan_options()}
          />
          <div :if={@form[:meal_plan].value in ["half_board", "full_board"]}>
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <.input
                field={@form[:meal_adults]}
                type="number"
                label="Dospělí ke stravování"
                min="0"
                step="1"
              />
              <.input
                field={@form[:meal_children]}
                type="number"
                label="Děti ke stravování"
                min="0"
                step="1"
              />
              <.input
                field={@form[:first_meal]}
                type="select"
                label="První jídlo (den příjezdu)"
                prompt="Vyberte jídlo"
                options={meal_options()}
                required
              />
              <.input
                field={@form[:last_meal]}
                type="select"
                label="Poslední jídlo (den odjezdu)"
                prompt="Vyberte jídlo"
                options={meal_options()}
                required
              />
            </div>
            <p class="mt-3 text-sm text-primary-400">
              Počty lze doplnit později. Pro výpočet porcí vyplňte oba počty včetně nul.
              Polopenze zahrnuje snídani a večeři.
            </p>
          </div>
        </fieldset>

        <.input
          field={@form[:dietary_restrictions]}
          type="textarea"
          label="Dietary Restrictions & Allergies"
          rows="3"
          placeholder="e.g., Gluten allergy, Vegetarian, No dairy"
        />

        <div class="mt-6 flex items-center justify-end gap-x-6">
          <.button type="submit" phx-disable-with="Saving...">Save Booking</.button>
        </div>
      </.form>

      <.modal
        :if={@show_guest_modal}
        id="guest-modal"
        show
        on_cancel={JS.push("hide_create_guest_modal", target: @myself)}
      >
        <.live_component
          module={CozyCheckoutWeb.BookingLive.GuestFormComponent}
          id={:new_guest}
          title="Create New Guest"
          action={:new}
          prefill_name={@guest_search_text}
        />
      </.modal>
    </div>
    """
  end

  @impl true
  def update(%{booking: booking} = assigns, socket) do
    rooms = Rooms.list_rooms()

    selected_room_ids =
      if booking.id do
        Bookings.list_booking_rooms(booking.id) |> Enum.map(& &1.id)
      else
        []
      end

    # Pre-populate guest search if editing
    {guest_search_text, selected_guest_id, selected_guest_name} =
      if booking.guest_id do
        guest = Guests.get_guest!(booking.guest_id)
        {guest.name, guest.id, guest.name}
      else
        {"", nil, nil}
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:rooms, rooms)
     |> assign(:selected_room_ids, selected_room_ids)
     |> assign(:room_error, nil)
     |> assign(
       :calendar_month,
       Date.beginning_of_month(booking.check_in_date || Date.utc_today())
     )
     |> assign(:range_start, nil)
     |> assign(:guest_search_text, guest_search_text)
     |> assign(:guest_suggestions, [])
     |> assign(:show_suggestions, false)
     |> assign(:selected_guest_id, selected_guest_id)
     |> assign(:selected_guest_name, selected_guest_name)
     |> assign(:show_guest_modal, false)
     |> assign_new(:form, fn ->
       to_form(Bookings.change_booking(booking))
     end)}
  end

  @impl true
  def update(%{guest_created: guest}, socket) do
    # Handle guest creation from the modal
    {:ok,
     socket
     |> assign(:selected_guest_id, guest.id)
     |> assign(:selected_guest_name, guest.name)
     |> assign(:guest_search_text, guest.name)
     |> assign(:show_guest_modal, false)
     |> put_flash(:success, "Guest created successfully")}
  end

  @impl true
  def handle_event("toggle_room", %{"room-id" => room_id}, socket) do
    selected_room_ids = socket.assigns.selected_room_ids

    selected_room_ids =
      if room_id in selected_room_ids do
        List.delete(selected_room_ids, room_id)
      else
        [room_id | selected_room_ids]
      end

    {:noreply, assign(socket, selected_room_ids: selected_room_ids, room_error: nil)}
  end

  @impl true
  def handle_event("search_guest", %{"value" => query}, socket) do
    suggestions = Guests.search_guests(query)
    show_suggestions = String.length(query) >= 3

    {:noreply,
     socket
     |> assign(:guest_search_text, query)
     |> assign(:guest_suggestions, suggestions)
     |> assign(:show_suggestions, show_suggestions)}
  end

  @impl true
  def handle_event("select_guest", %{"guest-id" => guest_id, "guest-name" => guest_name}, socket) do
    {:noreply,
     socket
     |> assign(:selected_guest_id, guest_id)
     |> assign(:selected_guest_name, guest_name)
     |> assign(:guest_search_text, guest_name)
     |> assign(:show_suggestions, false)
     |> assign(:guest_suggestions, [])}
  end

  @impl true
  def handle_event("clear_guest", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_guest_id, nil)
     |> assign(:selected_guest_name, nil)
     |> assign(:guest_search_text, "")
     |> assign(:show_suggestions, false)
     |> assign(:guest_suggestions, [])}
  end

  @impl true
  def handle_event("show_create_guest_modal", _params, socket) do
    {:noreply, assign(socket, show_guest_modal: true, show_suggestions: false)}
  end

  @impl true
  def handle_event("hide_create_guest_modal", _params, socket) do
    {:noreply, assign(socket, show_guest_modal: false)}
  end

  @impl true
  def handle_event("validate", %{"booking" => booking_params} = params, socket) do
    # Auto-update check-out date when check-in date changes
    booking_params =
      if params["_target"] == ["booking", "check_in_date"] do
        maybe_update_checkout_date(booking_params, socket.assigns.form)
      else
        booking_params
      end

    changeset = Bookings.change_booking(socket.assigns.booking, booking_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"booking" => booking_params}, socket) do
    save_booking(socket, socket.assigns.action, booking_params)
  end

  def handle_event("calendar_month", %{"offset" => offset}, socket) do
    {:noreply,
     assign(
       socket,
       :calendar_month,
       Date.shift(socket.assigns.calendar_month, month: String.to_integer(offset))
     )}
  end

  def handle_event("calendar_day", %{"date" => value}, socket) do
    {:ok, date} = Date.from_iso8601(value)
    start = socket.assigns.range_start
    attrs = socket.assigns.form.params || %{}

    {attrs, next} =
      if start && Date.compare(date, start) == :gt do
        {Map.merge(attrs, %{"check_in_date" => to_string(start), "check_out_date" => value}), nil}
      else
        {Map.merge(attrs, %{"check_in_date" => value, "check_out_date" => ""}), date}
      end

    {:noreply,
     socket
     |> assign(:range_start, next)
     |> assign(
       :form,
       to_form(Bookings.change_booking(socket.assigns.booking, attrs), action: :validate)
     )}
  end

  defp date_value(value) when is_struct(value, Date), do: value

  defp date_value(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp date_value(_), do: nil

  defp nights_label(form) do
    first = date_value(form[:check_in_date].value)
    last = date_value(form[:check_out_date].value)

    if first && last && Date.compare(last, first) == :gt,
      do: "Počet nocí: #{Date.diff(last, first)}",
      else: "Odjezd lze doplnit později"
  end

  defp selected_date?(form, date) do
    first = date_value(form[:check_in_date].value)
    last = date_value(form[:check_out_date].value)

    first && Date.compare(date, first) != :lt &&
      ((is_nil(last) && date == first) || (last && Date.compare(date, last) != :gt))
  end

  defp calendar_padding(date) do
    count = Date.day_of_week(date) - 1
    if count == 0, do: [], else: 1..count
  end

  defp month_label(date) do
    months = ~w(leden únor březen duben květen červen červenec srpen září říjen listopad prosinec)
    "#{Enum.at(months, date.month - 1)} #{date.year}"
  end

  defp maybe_update_checkout_date(params, form) do
    previous = date_value(form[:check_in_date].value)
    last = date_value(form[:check_out_date].value)
    next = date_value(params["check_in_date"])

    if previous && last && next && Date.compare(last, previous) == :gt do
      Map.put(params, "check_out_date", to_string(Date.add(next, Date.diff(last, previous))))
    else
      params
    end
  end

  defp save_booking(socket, action, booking_params) do
    booking_params = Map.put(booking_params, "guest_id", socket.assigns.selected_guest_id)

    case Bookings.save_booking_with_rooms(
           socket.assigns.booking,
           booking_params,
           socket.assigns.selected_room_ids
         ) do
      {:ok, booking} ->
        notify_parent({:saved, booking})
        socket = put_flash(socket, :success, "Rezervace uložena")

        {:noreply,
         if(action == :edit,
           do: push_patch(socket, to: socket.assigns.patch),
           else: push_navigate(socket, to: ~p"/admin/bookings/#{booking}")
         )}

      {:error, {:rooms_not_available, _}} ->
        {:noreply, assign(socket, :room_error, "Vybrané pokoje nejsou v tomto termínu dostupné")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :form, to_form(cs))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
