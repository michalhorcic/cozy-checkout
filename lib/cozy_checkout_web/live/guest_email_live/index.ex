defmodule CozyCheckoutWeb.GuestEmailLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Bookings
  alias CozyCheckout.GuestEmails
  alias CozyCheckout.GuestEmails.TemplateCatalog

  @impl true
  def mount(_params, _session, socket) do
    [first_template | _] = templates = TemplateCatalog.list()
    {:ok, rendered_template} = TemplateCatalog.render(first_template.id)

    {:ok,
     socket
     |> assign(:page_title, "Emaily hostům")
     |> assign(:templates, templates)
     |> assign(:template_id, first_template.id)
     |> assign(:content_mode, :template)
     |> assign(:custom_body, "")
     |> assign(:subject, first_template.subject)
     |> assign(:preview_html, rendered_template.html)
     |> assign(:preview_subject, rendered_template.subject)
     |> assign(:preview_booking_id, nil)
     |> assign(:preview_booking, nil)
     |> assign(:mailer_configured?, GuestEmails.configured?())
     |> assign(:email_from_address, Application.fetch_env!(:cozy_checkout, :email_from_address))
     |> assign(:period, :upcoming)
     |> assign(:search, "")
     |> assign(:bookings_empty?, true)
     |> assign(:selected_booking_ids, MapSet.new())
     |> assign(:selected_bookings_by_id, %{})
     |> assign(:selected_bookings, [])
     |> assign(:greeting_names, %{})
     |> assign(:extra_emails, %{})
     |> assign(:batch_id, nil)
     |> assign(:batch_complete?, false)
     |> assign(:batch_jobs_empty?, true)
     |> stream(:bookings, [])
     |> stream(:batch_jobs, [])}
  end

  defp refresh_preview_or_flash(socket) do
    case refresh_content_preview(socket) do
      {:ok, socket} ->
        socket

      {:error, reason, socket} ->
        put_flash(socket, :error, "Náhled emailu se nepodařilo obnovit: #{inspect(reason)}")
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    period = parse_period(params["period"])
    search = params["search"] || ""
    bookings = Bookings.list_bookings_for_email(period, search)

    socket =
      socket
      |> assign(:period, period)
      |> assign(:search, search)
      |> assign(:bookings_empty?, bookings == [])
      |> assign(:visible_bookings_by_id, Map.new(bookings, &{&1.id, &1}))
      |> stream(:bookings, bookings, reset: true)
      |> load_batch(params["batch_id"])

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_bookings", %{"filters" => params}, socket) do
    period = parse_period(params["period"])
    search = params["search"] || ""
    bookings = Bookings.list_bookings_for_email(period, search)

    {:noreply,
     socket
     |> assign(:period, period)
     |> assign(:search, search)
     |> assign(:bookings_empty?, bookings == [])
     |> assign(:visible_bookings_by_id, Map.new(bookings, &{&1.id, &1}))
     |> stream(:bookings, bookings, reset: true)}
  end

  def handle_event("toggle_booking", %{"booking-id" => booking_id}, socket) do
    selected_ids = socket.assigns.selected_booking_ids
    selected_bookings = socket.assigns.selected_bookings_by_id

    {selected_ids, selected_bookings} =
      if MapSet.member?(selected_ids, booking_id) do
        {MapSet.delete(selected_ids, booking_id), Map.delete(selected_bookings, booking_id)}
      else
        case Map.fetch(socket.assigns.visible_bookings_by_id, booking_id) do
          {:ok, booking} ->
            {MapSet.put(selected_ids, booking_id),
             Map.put(selected_bookings, booking_id, booking)}

          :error ->
            {selected_ids, selected_bookings}
        end
      end

    {:noreply, assign_selected_bookings(socket, selected_ids, selected_bookings)}
  end

  def handle_event(
        "update_extra_emails",
        %{"booking-id" => booking_id, "emails" => emails},
        socket
      ) do
    {:noreply,
     assign(socket, :extra_emails, Map.put(socket.assigns.extra_emails, booking_id, emails))}
  end

  def handle_event(
        "update_greeting_name",
        %{"greeting" => %{"booking_id" => booking_id, "name" => name}},
        socket
      ) do
    if Map.has_key?(socket.assigns.selected_bookings_by_id, booking_id) do
      greeting_names =
        case String.trim(name) do
          "" -> Map.delete(socket.assigns.greeting_names, booking_id)
          trimmed_name -> Map.put(socket.assigns.greeting_names, booking_id, trimmed_name)
        end

      socket =
        socket
        |> assign(:greeting_names, greeting_names)
        |> refresh_preview_or_flash()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_email_content", %{"email_content" => params}, socket) do
    template_id = params["template_id"] || socket.assigns.template_id

    case TemplateCatalog.fetch(template_id) do
      {:ok, template} ->
        mode =
          case params["mode"] do
            "custom" -> :custom
            "template" -> :template
            nil -> socket.assigns.content_mode
            _invalid -> socket.assigns.content_mode
          end

        custom_body = params["custom_body"] || socket.assigns.custom_body
        preview_booking_id = params["preview_booking_id"] || socket.assigns.preview_booking_id

        subject =
          if template_id != socket.assigns.template_id do
            template.subject
          else
            params["subject"] || socket.assigns.subject
          end

        socket =
          socket
          |> assign(:template_id, template_id)
          |> assign(:content_mode, mode)
          |> assign(:custom_body, custom_body)
          |> assign(:subject, subject)
          |> assign_preview_booking(preview_booking_id)

        case refresh_content_preview(socket) do
          {:ok, socket} ->
            {:noreply, socket}

          {:error, reason, socket} ->
            {:noreply,
             put_flash(socket, :error, "Obsah emailu se nepodařilo připravit: #{inspect(reason)}")}
        end

      {:error, :unknown_template} ->
        {:noreply, put_flash(socket, :error, "Vybraná šablona není dostupná.")}
    end
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply,
     socket
     |> assign(:greeting_names, %{})
     |> assign_selected_bookings(MapSet.new(), %{})}
  end

  def handle_event("send_emails", _params, socket) do
    cond do
      not socket.assigns.mailer_configured? ->
        {:noreply, put_flash(socket, :error, "Odesílání emailů není na serveru nakonfigurováno.")}

      socket.assigns.selected_bookings == [] ->
        {:noreply, put_flash(socket, :error, "Nejprve vyberte alespoň jednu rezervaci.")}

      batch_in_progress?(socket.assigns.batch_id) ->
        {:noreply, put_flash(socket, :error, "Předchozí rozesílka se ještě zpracovává.")}

      true ->
        enqueue_selected_emails(socket)
    end
  end

  @impl true
  def handle_info(:refresh_batch, socket) do
    {:noreply, refresh_batch(socket)}
  end

  defp enqueue_selected_emails(socket) do
    with {:ok, deliveries} <-
           build_deliveries(
             socket.assigns.selected_bookings,
             socket.assigns.extra_emails,
             socket.assigns.greeting_names
           ),
         {:ok, batch} <-
           GuestEmails.enqueue_batch(
             selected_content(socket.assigns),
             socket.assigns.subject,
             deliveries
           ) do
      params =
        %{
          "period" => Atom.to_string(socket.assigns.period),
          "batch_id" => batch.batch_id
        }
        |> maybe_put("search", socket.assigns.search)

      {:noreply,
       socket
       |> put_flash(:info, "Do fronty zařazeno #{length(batch.jobs)} emailů.")
       |> push_patch(to: ~p"/admin/emails?#{params}")}
    else
      {:error, {:missing_recipient, booking_name}} ->
        {:noreply,
         put_flash(socket, :error, "Rezervace #{booking_name} nemá žádného emailového příjemce.")}

      {:error, {:invalid_addresses, booking_name}} ->
        {:noreply,
         put_flash(socket, :error, "Zkontrolujte emailové adresy u rezervace #{booking_name}.")}

      {:error, :invalid_subject} ->
        {:noreply, put_flash(socket, :error, "Předmět emailu musí mít 1 až 255 znaků.")}

      {:error, :empty_body} ->
        {:noreply, put_flash(socket, :error, "Vlastní text emailu nesmí být prázdný.")}

      {:error, :no_recipients} ->
        {:noreply, put_flash(socket, :error, "Nebyli nalezeni žádní příjemci.")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Email se nepodařilo zařadit do fronty: #{inspect(reason)}")}
    end
  end

  defp selected_content(%{content_mode: :custom, custom_body: body}),
    do: %{type: :custom, body: body}

  defp selected_content(%{template_id: template_id}),
    do: %{type: :template, template_id: template_id}

  defp preview_content(:custom, body, subject) do
    preview_body = if String.trim(body) == "", do: "Náhled vlastního textu emailu", else: body

    case TemplateCatalog.render_custom(preview_body) do
      {:ok, rendered} -> {:ok, rendered.html, subject}
      {:error, reason} -> {:error, reason}
    end
  end

  defp assign_selected_bookings(socket, selected_ids, selected_by_id) do
    selected_bookings =
      selected_by_id
      |> Map.values()
      |> Enum.sort_by(&{&1.check_in_date, &1.guest.name})

    socket =
      socket
      |> assign(:selected_booking_ids, selected_ids)
      |> assign(:selected_bookings_by_id, selected_by_id)
      |> assign(:selected_bookings, selected_bookings)
      |> assign_preview_booking(socket.assigns.preview_booking_id)

    case refresh_content_preview(socket) do
      {:ok, socket} ->
        socket

      {:error, reason, socket} ->
        put_flash(socket, :error, "Náhled emailu se nepodařilo obnovit: #{inspect(reason)}")
    end
  end

  defp assign_preview_booking(socket, requested_id) do
    booking =
      Enum.find(socket.assigns.selected_bookings, &(&1.id == requested_id)) ||
        List.first(socket.assigns.selected_bookings)

    socket
    |> assign(:preview_booking, booking)
    |> assign(:preview_booking_id, booking && booking.id)
  end

  defp greeting_name(_assigns, nil), do: nil

  defp greeting_name(assigns, booking) do
    Map.get(assigns.greeting_names, booking.id)
  end

  defp refresh_content_preview(socket) do
    result =
      case socket.assigns.content_mode do
        :template ->
          case TemplateCatalog.render(
                 socket.assigns.template_id,
                 socket.assigns.preview_booking,
                 socket.assigns.subject,
                 greeting_name(socket.assigns, socket.assigns.preview_booking)
               ) do
            {:ok, template} -> {:ok, template.html, template.subject}
            {:error, reason} -> {:error, reason}
          end

        :custom ->
          preview_content(:custom, socket.assigns.custom_body, socket.assigns.subject)
      end

    case result do
      {:ok, html, preview_subject} ->
        {:ok,
         socket
         |> assign(:preview_html, html)
         |> assign(:preview_subject, preview_subject)}

      {:error, reason} ->
        {:error, reason, socket}
    end
  end

  defp build_deliveries(bookings, extra_emails, greeting_names) do
    Enum.reduce_while(bookings, {:ok, []}, fn booking, {:ok, acc} ->
      primary_email = booking.guest.email
      extras = split_emails(Map.get(extra_emails, booking.id, ""))
      emails = [primary_email | extras] |> Enum.reject(&is_nil/1) |> Enum.map(&String.trim/1)

      cond do
        Enum.any?(emails, &(not GuestEmails.valid_email?(&1))) ->
          {:halt, {:error, {:invalid_addresses, booking.guest.name}}}

        emails == [] ->
          {:halt, {:error, {:missing_recipient, booking.guest.name}}}

        true ->
          deliveries =
            emails
            |> Enum.uniq_by(&String.downcase/1)
            |> Enum.map(fn email ->
              %{
                booking_id: booking.id,
                booking_name: booking.guest.name,
                greeting_name: Map.get(greeting_names, booking.id),
                recipient_email: email
              }
            end)

          {:cont, {:ok, acc ++ deliveries}}
      end
    end)
  end

  defp split_emails(value) when is_binary(value) do
    value
    |> String.split(~r/[\s,;]+/, trim: true)
  end

  defp split_emails(_value), do: []

  defp load_batch(socket, batch_id) do
    case Ecto.UUID.cast(batch_id || "") do
      {:ok, canonical_id} ->
        socket
        |> assign(:batch_id, canonical_id)
        |> refresh_batch()

      :error ->
        socket
        |> assign(:batch_id, nil)
        |> assign(:batch_complete?, false)
        |> assign(:batch_jobs_empty?, true)
        |> stream(:batch_jobs, [], reset: true)
    end
  end

  defp refresh_batch(%{assigns: %{batch_id: nil}} = socket), do: socket

  defp refresh_batch(socket) do
    jobs = GuestEmails.list_batch_jobs(socket.assigns.batch_id)
    jobs_empty? = jobs == []
    complete? = jobs != [] and Enum.all?(jobs, &terminal_job?/1)

    socket =
      socket
      |> assign(:batch_jobs_empty?, jobs_empty?)
      |> assign(:batch_complete?, complete?)
      |> stream(:batch_jobs, jobs, reset: true)

    if jobs != [] and not complete?, do: Process.send_after(self(), :refresh_batch, 1_500)
    socket
  end

  defp batch_in_progress?(nil), do: false

  defp batch_in_progress?(batch_id) do
    case GuestEmails.list_batch_jobs(batch_id) do
      [] -> false
      jobs -> not Enum.all?(jobs, &terminal_job?/1)
    end
  end

  defp terminal_job?(%Oban.Job{state: state}),
    do: state in ["completed", "discarded", "cancelled"]

  defp parse_period("past"), do: :past
  defp parse_period("all"), do: :all
  defp parse_period(_period), do: :upcoming

  defp maybe_put(params, _key, ""), do: params
  defp maybe_put(params, key, value), do: Map.put(params, key, value)

  defp job_state_label("available"), do: "Čeká ve frontě"
  defp job_state_label("scheduled"), do: "Naplánováno k opakování"
  defp job_state_label("executing"), do: "Odesílá se"
  defp job_state_label("retryable"), do: "Opakuje se"
  defp job_state_label("completed"), do: "Přijato Resendem"
  defp job_state_label("discarded"), do: "Selhalo"
  defp job_state_label("cancelled"), do: "Zrušeno"
  defp job_state_label(_state), do: "Ve frontě"

  defp job_state_class("completed"), do: "bg-emerald-100 text-emerald-800"

  defp job_state_class(state) when state in ["discarded", "cancelled"],
    do: "bg-rose-100 text-rose-800"

  defp job_state_class(_state), do: "bg-amber-100 text-amber-800"

  defp job_error(%Oban.Job{errors: errors}) when is_list(errors) do
    case List.last(errors) do
      %{"error" => error} -> error
      %{error: error} -> inspect(error)
      _ -> nil
    end
  end

  defp job_error(_job), do: nil

  defp booking_noun(1), do: "rezervace"
  defp booking_noun(count) when count in 2..4, do: "rezervace"
  defp booking_noun(_count), do: "rezervací"

  defp recipient_noun(1), do: "adresát"
  defp recipient_noun(count) when count in 2..4, do: "adresáti"
  defp recipient_noun(_count), do: "adresátů"

  defp email_count(bookings, extra_emails) do
    Enum.reduce(bookings, 0, fn booking, count ->
      [booking.guest.email | split_emails(Map.get(extra_emails, booking.id, ""))]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&String.trim/1)
      |> Enum.uniq_by(&String.downcase/1)
      |> then(&(count + length(&1)))
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      flash_info_class="alert-success"
      show_header={false}
      main_class="p-0"
      content_class="max-w-none space-y-0"
    >
      <div class="min-h-screen bg-gradient-to-br from-slate-50 via-white to-sky-50 px-4 py-8 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-7xl">
          <div class="mb-8 flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <.link
                navigate={~p"/admin"}
                class="mb-3 inline-flex items-center gap-2 text-sm font-semibold text-slate-500 hover:text-slate-800"
              >
                <.icon name="hero-arrow-left" class="h-4 w-4" /> Administrace
              </.link>
              <h1 class="text-3xl font-bold tracking-tight text-slate-900 sm:text-4xl">
                {@page_title}
              </h1>
              <p class="mt-2 max-w-2xl text-slate-600">
                Vyberte rezervace a připravte email ze šablony nebo vlastním textem. Každý host dostane vlastní email.
              </p>
            </div>
            <div class="rounded-2xl border border-sky-100 bg-white px-5 py-4 shadow-sm">
              <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">Odesílatel</p>
              <p class="mt-1 font-semibold text-slate-900">{@email_from_address}</p>
            </div>
          </div>

          <div
            :if={!@mailer_configured?}
            id="email-provider-warning"
            class="mb-6 rounded-xl border border-amber-200 bg-amber-50 p-4 text-amber-900"
          >
            <strong>Odesílání není nakonfigurováno.</strong>
            <span> Na produkčním serveru nastavte secret <code>RESEND_API_KEY</code>
            a ověřte doménu v Resendu.</span>
          </div>

          <div class="grid gap-6 xl:grid-cols-[minmax(0,1fr)_minmax(360px,0.85fr)]">
            <section class="rounded-2xl border border-slate-200 bg-white shadow-sm">
              <div class="border-b border-slate-100 px-5 py-5 sm:px-6">
                <div class="flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <h2 class="text-lg font-bold text-slate-900">1. Vyberte rezervace</h2>
                    <p class="mt-1 text-sm text-slate-500">
                      Vybráno {@selected_booking_ids |> MapSet.size()} {booking_noun(
                        MapSet.size(@selected_booking_ids)
                      )} · {email_count(@selected_bookings, @extra_emails)} {recipient_noun(
                        email_count(@selected_bookings, @extra_emails)
                      )}
                    </p>
                  </div>
                  <button
                    :if={MapSet.size(@selected_booking_ids) > 0}
                    type="button"
                    id="clear-booking-selection"
                    phx-click="clear_selection"
                    class="rounded-lg px-3 py-2 text-sm font-semibold text-slate-600 transition hover:bg-slate-100"
                  >
                    Zrušit výběr
                  </button>
                </div>

                <form
                  id="booking-email-filters"
                  phx-change="filter_bookings"
                  class="mt-5 grid gap-3 sm:grid-cols-[minmax(0,1fr)_minmax(220px,1.2fr)]"
                >
                  <label class="block">
                    <span class="mb-1.5 block text-sm font-semibold text-slate-700">Období</span>
                    <select
                      id="booking-email-period"
                      name="filters[period]"
                      class="w-full rounded-xl border border-slate-300 bg-white px-3 py-2.5 text-sm text-slate-900 focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200"
                    >
                      <option value="upcoming" selected={@period == :upcoming}>
                        Budoucí příjezdy
                      </option>
                      <option value="past" selected={@period == :past}>Minulé pobyty</option>
                      <option value="all" selected={@period == :all}>Všechny rezervace</option>
                    </select>
                  </label>
                  <label class="block">
                    <span class="mb-1.5 block text-sm font-semibold text-slate-700">Hledat hosta</span>
                    <input
                      id="booking-email-search"
                      type="search"
                      name="filters[search]"
                      value={@search}
                      placeholder="Jméno nebo email"
                      phx-debounce="300"
                      class="w-full rounded-xl border border-slate-300 bg-white px-3 py-2.5 text-sm text-slate-900 placeholder:text-slate-400 focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200"
                    />
                  </label>
                </form>
              </div>

              <div
                id="email-bookings"
                phx-update="stream"
                class="max-h-[680px] divide-y divide-slate-100 overflow-y-auto"
              >
                <article
                  :for={{dom_id, booking} <- @streams.bookings}
                  id={dom_id}
                  class="p-5 transition hover:bg-slate-50/80 sm:px-6"
                >
                  <div class="flex items-start gap-3">
                    <input
                      id={"email-booking-#{booking.id}"}
                      type="checkbox"
                      checked={MapSet.member?(@selected_booking_ids, booking.id)}
                      phx-click="toggle_booking"
                      phx-value-booking-id={booking.id}
                      class="mt-1 h-5 w-5 rounded border-slate-300 text-sky-600 focus:ring-sky-500"
                    />
                    <div class="min-w-0 flex-1">
                      <label
                        for={"email-booking-#{booking.id}"}
                        class="cursor-pointer font-semibold text-slate-900"
                      >
                        {booking.guest.name}
                      </label>
                      <p class="mt-1 text-sm text-slate-500">
                        Příjezd {Calendar.strftime(booking.check_in_date, "%d.%m.%Y")}
                        <span :if={booking.check_out_date}> · odjezd {Calendar.strftime(
                          booking.check_out_date,
                          "%d.%m.%Y"
                        )}</span>
                        <span class="ml-1 rounded-full bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-600">{booking.status}</span>
                      </p>

                      <div class="mt-3 grid gap-3 sm:grid-cols-2">
                        <div class="rounded-lg bg-slate-50 px-3 py-2">
                          <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">
                            Email hosta
                          </p>
                          <p class="mt-1 break-all text-sm text-slate-800">
                            {booking.guest.email || "Není uložen — zadejte adresu ručně"}
                          </p>
                        </div>
                        <form
                          id={"extra-email-form-#{booking.id}"}
                          phx-change="update_extra_emails"
                          phx-value-booking-id={booking.id}
                        >
                          <label
                            for={"extra-emails-#{booking.id}"}
                            class="mb-1 block text-xs font-semibold uppercase tracking-wide text-slate-500"
                          >
                            Další adresy
                          </label>
                          <input
                            id={"extra-emails-#{booking.id}"}
                            name="emails"
                            type="text"
                            value={Map.get(@extra_emails, booking.id, "")}
                            placeholder="partner@example.com"
                            autocomplete="off"
                            phx-debounce="300"
                            class="w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 placeholder:text-slate-400 focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200"
                          />
                        </form>
                      </div>
                    </div>
                  </div>
                </article>
              </div>
              <div :if={@bookings_empty?} class="px-6 py-12 text-center text-slate-500">
                Pro zvolené období nebyly nalezeny žádné rezervace.
              </div>
            </section>

            <div class="space-y-6">
              <section class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
                <h2 class="text-lg font-bold text-slate-900">2. Připravte email</h2>
                <form id="email-content-form" phx-change="update_email_content">
                  <label
                    for="email-content-mode"
                    class="mb-1.5 mt-5 block text-sm font-semibold text-slate-700"
                  >Způsob přípravy</label>
                  <select
                    id="email-content-mode"
                    name="email_content[mode]"
                    value={@content_mode}
                    class="w-full rounded-xl border border-slate-300 bg-white px-3 py-3 text-sm text-slate-900 focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200"
                  >
                    <option value="template" selected={@content_mode == :template}>
                      Použít šablonu
                    </option>
                    <option value="custom" selected={@content_mode == :custom}>
                      Napsat vlastní text
                    </option>
                  </select>

                  <div :if={@content_mode == :template}>
                    <label
                      for="email-template"
                      class="mb-1.5 mt-4 block text-sm font-semibold text-slate-700"
                    >Šablona</label>
                    <select
                      id="email-template"
                      name="email_content[template_id]"
                      value={@template_id}
                      class="w-full rounded-xl border border-slate-300 bg-white px-3 py-3 text-sm text-slate-900 focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200"
                    >
                      <option
                        :for={template <- @templates}
                        value={template.id}
                        selected={template.id == @template_id}
                      >
                        {template.label}
                      </option>
                    </select>
                  </div>

                  <label
                    :if={@content_mode == :custom}
                    for="email-custom-body"
                    class="mb-1.5 mt-4 block text-sm font-semibold text-slate-700"
                  >Vlastní text</label>
                  <textarea
                    :if={@content_mode == :custom}
                    id="email-custom-body"
                    name="email_content[custom_body]"
                    rows="8"
                    phx-debounce="300"
                    placeholder="Napište text zprávy. Řádky a odstavce se zachovají."
                    class="w-full rounded-xl border border-slate-300 bg-white px-3 py-3 text-sm text-slate-900 placeholder:text-slate-400 focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200"
                  >{@custom_body}</textarea>

                  <label
                    for="email-subject"
                    class="mb-1.5 mt-4 block text-sm font-semibold text-slate-700"
                  >Předmět</label>
                  <input
                    id="email-subject"
                    name="email_content[subject]"
                    type="text"
                    value={@subject}
                    maxlength="255"
                    class="w-full rounded-xl border border-slate-300 bg-white px-3 py-3 text-sm text-slate-900 focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200"
                  />

                  <label
                    :if={length(@selected_bookings) > 0}
                    for="email-preview-booking"
                    class="mb-1.5 mt-4 block text-sm font-semibold text-slate-700"
                  >Náhled pro rezervaci</label>
                  <select
                    :if={length(@selected_bookings) > 0}
                    id="email-preview-booking"
                    name="email_content[preview_booking_id]"
                    class="w-full rounded-xl border border-slate-300 bg-white px-3 py-3 text-sm text-slate-900 focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200"
                  >
                    <option
                      :for={booking <- @selected_bookings}
                      value={booking.id}
                      selected={booking.id == @preview_booking_id}
                    >
                      {booking.guest.name} · {Calendar.strftime(booking.check_in_date, "%d.%m.%Y")}
                    </option>
                  </select>
                </form>

                <form
                  :if={@preview_booking && @content_mode == :template}
                  id="email-greeting-form"
                  phx-change="update_greeting_name"
                  class="mt-4"
                >
                  <input
                    type="hidden"
                    name="greeting[booking_id]"
                    value={@preview_booking.id}
                  />
                  <label
                    for="email-greeting-name"
                    class="mb-1.5 block text-sm font-semibold text-slate-700"
                  >Jméno v pozdravu</label>
                  <input
                    id="email-greeting-name"
                    name="greeting[name]"
                    type="text"
                    value={Map.get(@greeting_names, @preview_booking.id, @preview_booking.guest.name)}
                    autocomplete="off"
                    phx-debounce="300"
                    placeholder={@preview_booking.guest.name}
                    class="w-full rounded-xl border border-slate-300 bg-white px-3 py-3 text-sm text-slate-900 focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200"
                  />
                  <p class="mt-1.5 text-xs text-slate-500">
                    Upravte oslovení (např. „Petře Nováku“). Prázdné pole použije jméno hosta z rezervace. Změna platí jen pro tento email.
                  </p>
                </form>

                <div class="mt-5 rounded-xl border border-slate-200 bg-slate-50 p-3">
                  <div class="mb-2 flex items-center justify-between">
                    <h3 class="text-sm font-semibold text-slate-700">Náhled emailu</h3>
                    <span class="text-xs text-slate-500">
                      {if @content_mode == :template, do: "HTML šablona", else: "Vlastní text"}
                    </span>
                  </div>
                  <p id="email-preview-subject" class="mb-2 text-sm font-medium text-slate-700">
                    Předmět: {@preview_subject}
                  </p>
                  <p :if={@preview_booking} class="mb-2 text-xs text-slate-500">
                    Náhled pro: {@preview_booking.guest.name}
                  </p>
                  <iframe
                    id="email-template-preview"
                    title="Náhled emailu"
                    sandbox=""
                    srcdoc={@preview_html}
                    class="h-[420px] w-full rounded-lg bg-white shadow-inner"
                  />
                </div>
              </section>

              <section class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
                <h2 class="text-lg font-bold text-slate-900">3. Zkontrolujte a zařaďte</h2>
                <p class="mt-2 text-sm leading-6 text-slate-600">
                  Každý z {@selected_booking_ids |> MapSet.size()} vybraných hostů obdrží samostatný email. Další adresy jsou oddělené středníkem, čárkou nebo mezerou.
                </p>
                <button
                  id="queue-booking-emails"
                  type="button"
                  phx-click="send_emails"
                  data-confirm={"Zařadit #{email_count(@selected_bookings, @extra_emails)} emailů do fronty?"}
                  phx-disable-with="Zařazuji…"
                  disabled={!@mailer_configured? || @selected_bookings == []}
                  class="mt-5 inline-flex w-full items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-sky-600 to-indigo-600 px-5 py-3.5 font-semibold text-white shadow-md transition hover:-translate-y-0.5 hover:from-sky-700 hover:to-indigo-700 hover:shadow-lg focus:outline-none focus:ring-4 focus:ring-sky-200 disabled:cursor-not-allowed disabled:opacity-45"
                >
                  <.icon name="hero-paper-airplane" class="h-5 w-5" /> Zařadit do fronty
                </button>
                <p class="mt-3 text-center text-xs text-slate-500">
                  Odeslání zpracuje fronta na pozadí a při dočasné chybě se automaticky zopakuje.
                </p>
              </section>
            </div>
          </div>

          <section
            :if={@batch_id}
            id="current-email-batch"
            class="mt-8 rounded-2xl border border-slate-200 bg-white shadow-sm"
          >
            <div class="flex flex-wrap items-center justify-between gap-3 border-b border-slate-100 px-5 py-5 sm:px-6">
              <div>
                <h2 class="text-lg font-bold text-slate-900">Aktuální rozesílka</h2>
                <p class="mt-1 text-sm text-slate-500">
                  {@batch_id}
                  <span :if={@batch_complete?}> · Zpracování dokončeno</span>
                  <span :if={!@batch_complete?}> · Zpracovává se</span>
                </p>
              </div>
              <span
                :if={!@batch_complete?}
                class="inline-flex items-center gap-2 rounded-full bg-sky-50 px-3 py-1.5 text-sm font-semibold text-sky-800"
              >
                <.icon name="hero-arrow-path" class="h-4 w-4 animate-spin" /> Aktualizace stavu
              </span>
            </div>
            <div :if={@batch_jobs_empty?} class="px-6 py-8 text-sm text-slate-500">
              Pro tuto rozesílku zatím nejsou dostupné žádné úlohy.
            </div>
            <div id="email-batch-jobs" phx-update="stream" class="divide-y divide-slate-100">
              <div
                :for={{dom_id, job} <- @streams.batch_jobs}
                id={dom_id}
                class="flex flex-col gap-2 px-5 py-4 sm:flex-row sm:items-center sm:justify-between sm:px-6"
              >
                <div class="min-w-0">
                  <p class="break-all font-medium text-slate-900">{job.args["recipient_email"]}</p>
                  <p class="mt-0.5 text-sm text-slate-500">{job.args["booking_name"]}</p>
                  <p :if={job_error(job)} class="mt-1 text-sm text-rose-700">{job_error(job)}</p>
                </div>
                <span class={[
                  "w-fit shrink-0 rounded-full px-3 py-1 text-xs font-semibold",
                  job_state_class(job.state)
                ]}>
                  {job_state_label(job.state)}
                </span>
              </div>
            </div>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
