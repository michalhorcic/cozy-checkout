defmodule CozyCheckoutWeb.BillingLive.Settings do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Billing
  alias CozyCheckoutWeb.BillingLive.Helpers

  @fields [
    {"name", "Název společnosti"},
    {"street", "Sídlo – ulice a číslo"},
    {"city", "Město"},
    {"postcode", "PSČ"},
    {"country", "Země (CZ)"},
    {"company_id", "IČO"},
    {"vat_id", "DIČ"},
    {"registry", "Zápis v rejstříku (soud, oddíl, vložka)"},
    {"email", "E-mail"},
    {"phone", "Telefon"},
    {"bank_account", "Český účet (číslo/kód banky)"},
    {"iban", "IBAN"},
    {"due_days", "Splatnost ve dnech"}
  ]
  def mount(_, _, socket) do
    {:ok,
     assign(socket,
       page_title: "Nastavení fakturace",
       fields: @fields,
       form: to_form(Billing.profile().data, as: :profile),
       series: Billing.list_series(),
       series_form: series_form()
     )}
  end

  def handle_event("profile", %{"profile" => attrs}, socket) do
    case Billing.save_profile(attrs) do
      {:ok, profile} ->
        {:noreply,
         socket
         |> assign(:form, to_form(profile.data, as: :profile))
         |> put_flash(:info, "Dodavatel uložen")}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:form, to_form(attrs, as: :profile))
         |> put_flash(:error, Helpers.error(error))}
    end
  end

  def handle_event("series", %{"series" => attrs}, socket) do
    case Billing.save_series(attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:series, Billing.list_series())
         |> assign(:series_form, series_form())
         |> put_flash(:info, "Řada uložena")}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:series_form, to_form(attrs, as: :series))
         |> put_flash(:error, Helpers.error(error))}
    end
  end

  defp series_form,
    do:
      to_form(
        %{
          "kind" => "advance",
          "year" => to_string(Billing.today().year),
          "prefix" => "COZY-ZF",
          "digits" => "5",
          "next_number" => "1"
        },
        as: :series
      )

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-5xl mx-auto space-y-8">
        <h1 class="text-3xl font-bold">Nastavení fakturace</h1>
        <p>
          Nejdříve doplňte skutečné sídlo a údaje dodavatele a nastavte všechny čtyři řady podle účetní.
        </p>
        <.form
          for={@form}
          id="billing-profile"
          phx-submit="profile"
          class="bg-white rounded-xl p-6 grid md:grid-cols-2 gap-4"
        >
          <.input :for={{key, label} <- @fields} field={@form[key]} label={label} />
          <button class="btn btn-primary md:col-span-2">Uložit dodavatele</button>
        </.form>
        <section class="bg-white rounded-xl p-6 space-y-4">
          <h2 class="text-xl font-bold">Číselné řady</h2>
          <p>
            Číslo tvoří označení + čtyřmístný rok + pořadové číslo. Např. FV202600001. Použitou řadu nelze měnit. Variabilní symbol se přiděluje samostatně a je jedinečný.
          </p>
          <table class="table">
            <thead>
              <tr>
                <th>Druh</th><th>Rok</th><th>Označení</th><th>Číslic</th><th>Další číslo</th>
              </tr>
            </thead><tbody>
              <tr :for={s <- @series}>
                <td>{Billing.kind_label(s.kind)}</td><td>{s.year}</td><td>{s.prefix}</td><td>
                  {s.digits}
                </td><td>{s.next_number}</td>
              </tr>
            </tbody>
          </table>
          <.form
            for={@series_form}
            id="billing-series"
            phx-submit="series"
            class="grid md:grid-cols-5 gap-3"
          >
            <.input field={@series_form[:kind]} type="select" label="Druh" options={Billing.kinds()} />
            <.input field={@series_form[:year]} type="number" label="Rok" min="2000" required />
            <.input field={@series_form[:prefix]} label="Označení" required />
            <.input
              field={@series_form[:digits]}
              type="number"
              label="Počet číslic"
              min="1"
              max="8"
              required
            />
            <.input
              field={@series_form[:next_number]}
              type="number"
              label="První číslo"
              min="1"
              required
            />
            <button class="btn btn-primary md:col-span-5">Uložit nepoužitou řadu</button>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
