defmodule CozyCheckoutWeb.KitchenCostsLive.Reports do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.KitchenCosts.Reports
  import CozyCheckoutWeb.KitchenCostsLive.Helpers

  @impl true
  def mount(_, _, socket),
    do: {:ok, socket |> assign(:page_title, "Náklady kuchyně") |> assign(:food_context, %{})}

  @impl true
  def handle_params(params, _, socket) do
    bookings =
      CozyCheckout.Bookings.list_bookings()
      |> Enum.reject(&(&1.status == "cancelled" or &1.meal_plan == "none"))

    socket =
      socket
      |> assign(:saved_reports, Reports.list())
      |> assign(:booking_options, [
        {"Všechny rezervace", ""}
        | Enum.map(bookings, &{"#{&1.guest.name} · #{&1.check_in_date}", &1.id})
      ])
      |> assign(:error, nil)

    if socket.assigns.live_action == :show do
      report = Reports.get!(params["id"])

      {:noreply,
       socket
       |> assign(:report, report.snapshot)
       |> assign(:saved, report)
       |> assign_range(report.snapshot)}
    else
      today = Date.to_iso8601(Date.utc_today())

      range = %{
        "from" => params["from"] || today,
        "to" => params["to"] || today,
        "booking" => params["booking"] || ""
      }

      socket = socket |> assign(:saved, nil) |> assign(:range, to_form(range, as: :range))

      case generate(range) do
        {:ok, result} ->
          {:noreply, assign(socket, :report, result)}

        {:error, reason} ->
          {:noreply, socket |> assign(:report, nil) |> assign(:error, range_error(reason))}
      end
    end
  end

  @impl true
  def handle_event("calculate", %{"range" => range}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/admin/kitchen-costs/reports?#{range}")}

  def handle_event("save", _, socket) do
    if socket.assigns.report && is_nil(socket.assigns.saved) do
      case Reports.save(socket.assigns.report) do
        {:ok, saved} ->
          {:noreply,
           socket
           |> put_flash(:success, "Neměnný report uložen.")
           |> push_navigate(to: ~p"/admin/kitchen-costs/reports/#{saved.id}")}

        {:error, reason} ->
          {:noreply, assign(socket, :error, error(reason))}
      end
    else
      {:noreply, socket}
    end
  end

  defp assign_range(socket, report),
    do:
      assign(
        socket,
        :range,
        to_form(
          %{
            "from" => report["start_date"],
            "to" => report["end_date"],
            "booking" => report["booking_id"] || ""
          },
          as: :range
        )
      )

  defp generate(range) do
    with {:ok, first} <- Date.from_iso8601(range["from"]),
         {:ok, last} <- Date.from_iso8601(range["to"]),
         do: Reports.generate(first, last, range["booking"])
  end

  defp range_error(:booking_unavailable),
    do: "Rezervace v tomto období není dostupná. Vyberte jinou nebo všechny rezervace."

  defp range_error(_), do: "Zvolte platné období nejvýše 366 dní."
  defp meal_label(type), do: CozyCheckout.Kitchen.ShoppingList.label(type)
end
