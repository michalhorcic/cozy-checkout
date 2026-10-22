defmodule CozyCheckoutWeb.BillingLive.Documents do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Billing
  alias CozyCheckoutWeb.BillingLive.Helpers
  def mount(_, _, socket), do: {:ok, assign(socket, page_title: "Doklady z rezervací")}

  def handle_params(%{"id" => id}, _, socket) do
    doc = Billing.get_document!(id)
    buyer = doc.snapshot["customer"]

    {:noreply,
     assign(socket,
       document: doc,
       deliveries: Billing.list_deliveries(id),
       correction_form:
         to_form(
           %{"request_id" => Ecto.UUID.generate(), "tax_date" => to_string(Billing.today())},
           as: :correction
         ),
       email_form:
         to_form(
           %{
             "request_id" => Ecto.UUID.generate(),
             "recipient" => buyer["email"] || "",
             "subject" => "#{Billing.kind_label(doc.kind)} #{doc.number}",
             "body" =>
               "Dobrý den,\n\nv příloze zasíláme doklad k Vašemu pobytu.\n\nJindřichův dům",
             "consent" => "false"
           },
           as: :email
         )
     )}
  end

  def handle_params(params, _, socket),
    do:
      {:noreply,
       assign(socket,
         document: nil,
         documents: Billing.list_documents(params),
         filter_form: to_form(Map.take(params, ["kind", "number"]), as: :filter)
       )}

  def handle_event("filter", %{"filter" => attrs}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/admin/billing?#{attrs}")}

  def handle_event("refresh", _, socket),
    do:
      {:noreply, assign(socket, :deliveries, Billing.list_deliveries(socket.assigns.document.id))}

  def handle_event("email", %{"email" => attrs}, socket) do
    case Billing.enqueue_email(socket.assigns.document.id, attrs, attrs["request_id"]) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:deliveries, Billing.list_deliveries(socket.assigns.document.id))
         |> assign(
           :email_form,
           to_form(Map.put(attrs, "request_id", Ecto.UUID.generate()), as: :email)
         )
         |> put_flash(:info, "E-mail zařazen k odeslání")}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:email_form, to_form(attrs, as: :email))
         |> put_flash(:error, Helpers.error(error))}
    end
  end

  def handle_event("correct", %{"correction" => attrs}, socket) do
    case Billing.correct(socket.assigns.document.id, attrs, attrs["request_id"]) do
      {:ok, doc} ->
        {:noreply, push_navigate(socket, to: ~p"/admin/billing/documents/#{doc.id}")}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:correction_form, to_form(attrs, as: :correction))
         |> put_flash(:error, Helpers.error(error))}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-6xl mx-auto space-y-6">
        <h1 class="text-3xl font-bold">Doklady z rezervací</h1>
        <nav class="flex gap-3">
          <.link navigate={~p"/admin/billing"} class="link">Seznam dokladů</.link><.link
            navigate={~p"/admin/billing/settings"}
            class="link"
          >Nastavení</.link><.link navigate={~p"/admin/accommodation-prices"} class="link">Ceník ubytování</.link>
        </nav>
        <div :if={!@document} class="space-y-4">
          <.form
            for={@filter_form}
            id="billing-filter"
            phx-submit="filter"
            class="flex gap-3 items-end"
          >
            <.input
              field={@filter_form[:kind]}
              type="select"
              label="Druh"
              options={[{"Všechny", ""}] ++ Billing.kinds()}
            /><.input field={@filter_form[:number]} label="Číslo obsahuje" /><button class="btn">Filtrovat</button>
          </.form>
          <div class="overflow-x-auto bg-white rounded-xl">
            <table class="table">
              <thead>
                <tr>
                  <th>Číslo</th><th>Druh</th><th>Odběratel</th><th>Vystaveno</th><th>Splatnost</th><th>
                    Celkem
                  </th>
                </tr>
              </thead><tbody>
                <tr :for={doc <- @documents}>
                  <td>
                    <.link class="link" navigate={~p"/admin/billing/documents/#{doc.id}"}>{doc.number}</.link>
                  </td><td>{Billing.kind_label(doc.kind)}</td><td>
                    {doc.snapshot["customer"]["name"]}
                  </td><td>{doc.issued_on}</td><td>{doc.due_on}</td><td>
                    {format_currency(doc.total)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        <div :if={@document} class="space-y-6">
          <section class="bg-white p-6 rounded-xl space-y-4">
            <h2 class="text-2xl font-bold">
              {Billing.kind_label(@document.kind)} {@document.number}
            </h2>
            <p>
              Odběratel: {@document.snapshot["customer"]["name"]} · Vystaveno {@document.issued_on} · DUZP / přijetí platby {@document.tax_date} · VS {@document.variable_symbol}
            </p>
            <p
              :if={
                @document.kind == "tax_receipt" &&
                  Date.diff(@document.issued_on, @document.tax_date) > 15
              }
              class="alert alert-warning"
            >
              Doklad byl vystaven více než 15 dnů po přijetí platby.
            </p>
            <p :if={@document.snapshot["reason"]}>
              Oprava {@document.snapshot["original_number"]}: {@document.snapshot["reason"]}
            </p>
            <p :for={line <- @document.lines}>{line["name"]}: {line["gross"]} CZK</p>
            <p :for={line <- @document.snapshot["deductions"] || []}>
              {line["name"]}: {line["gross"]} CZK
            </p>
            <p class="text-xl font-bold">Celkem {format_currency(@document.total)}</p>
            <div class="flex gap-3">
              <.link
                href={~p"/admin/billing/documents/#{@document.id}/pdf"}
                class="btn btn-primary"
                target="_blank"
              >Stáhnout uložené PDF</.link><.link
                navigate={~p"/admin/bookings/#{@document.booking_id}/billing"}
                class="btn"
              >Doklady a platby pobytu</.link>
            </div>
          </section>
          <section class="bg-white p-6 rounded-xl space-y-4">
            <h2 class="text-xl font-bold">Odeslat e-mailem</h2>
            <.form for={@email_form} id="billing-email" phx-submit="email" class="space-y-3">
              <input type="hidden" name="email[request_id]" value={@email_form[:request_id].value} />
              <.input field={@email_form[:recipient]} type="email" label="Příjemce" required /><.input
                field={@email_form[:subject]}
                label="Předmět"
                required
              /><.input field={@email_form[:body]} type="textarea" label="Zpráva" required />
              <.input
                field={@email_form[:consent]}
                type="checkbox"
                label="Odběratel souhlasí s elektronickou podobou daňového dokladu"
              />
              <button class="btn btn-primary" phx-disable-with="Zařazuji…">Odeslat s uloženým PDF</button>
            </.form>
            <button class="link" phx-click="refresh">Obnovit historii</button>
            <div :for={d <- @deliveries} class="border-b py-2">
              {d.recipient} · {delivery_label(d.state)} · pokusů {d.attempts}
              <p :if={d.state in ["failed", "retrying"]} class="text-red-700">
                Příprava PDF nebo odeslání se nezdařily.
              </p>
              <details :if={d.error && d.state in ["failed", "retrying"]}>
                <summary>Podrobnosti chyby</summary><pre class="whitespace-pre-wrap text-sm">{d.error}</pre>
              </details>
            </div>
            <p class="text-sm">
              Odesláno znamená přijetí poštovním poskytovatelem, nikoli potvrzené doručení adresátovi.
            </p>
          </section>
          <section
            :if={@document.kind in ["final", "tax_receipt"]}
            class="bg-white p-6 rounded-xl space-y-4"
          >
            <h2 class="text-xl font-bold">Opravný daňový doklad</h2>
            <p>
              Původní doklad zůstane zachovaný. Vratku peněz evidujte následně u pobytu. Lze snížit i zvýšit cenu; vždy uveďte důvod.
            </p>
            <.form
              for={@correction_form}
              id="billing-correction"
              phx-submit="correct"
              class="grid md:grid-cols-3 gap-3"
            >
              <input
                type="hidden"
                name="correction[request_id]"
                value={@correction_form[:request_id].value}
              />
              <.input
                field={@correction_form[:direction]}
                type="select"
                label="Změna ceny"
                options={[{"Snížení", "decrease"}, {"Zvýšení", "increase"}]}
              />
              <.input
                field={@correction_form[:amount]}
                type="number"
                step="0.01"
                min="0.01"
                label="Rozdíl celkové ceny"
                required
              /><.input field={@correction_form[:tax_date]} type="date" label="Datum opravy" required /><.input
                field={@correction_form[:reason]}
                label="Důvod opravy"
                required
              /><button class="btn btn-primary md:col-span-3" phx-disable-with="Vystavuji…">Vystavit opravu</button>
            </.form>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp delivery_label("accepted"), do: "Odesláno"
  defp delivery_label("queued"), do: "Ve frontě"
  defp delivery_label("retrying"), do: "Čeká na opakování"
  defp delivery_label(_), do: "Neodesláno"
end
