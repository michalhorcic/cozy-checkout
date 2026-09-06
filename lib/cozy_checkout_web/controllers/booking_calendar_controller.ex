defmodule CozyCheckoutWeb.BookingCalendarController do
  use CozyCheckoutWeb, :controller

  alias CozyCheckout.Bookings

  def index(conn, %{"token" => token}) do
    if valid_token?(token) do
      conn
      |> put_resp_content_type("text/calendar")
      |> put_resp_header("content-disposition", "inline; filename=bookings.ics")
      |> send_resp(200, Bookings.to_ical(Bookings.list_bookings_for_calendar()))
    else
      send_resp(conn, 404, "Not found")
    end
  end

  def index(conn, _params), do: send_resp(conn, 404, "Not found")

  defp valid_token?(provided_token) do
    case Application.get_env(:cozy_checkout, :booking_ical_token) do
      configured_token when is_binary(configured_token) and byte_size(configured_token) > 0 ->
        Plug.Crypto.secure_compare(provided_token, configured_token)

      _ ->
        false
    end
  end
end
