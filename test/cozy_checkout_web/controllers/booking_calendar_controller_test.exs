defmodule CozyCheckoutWeb.BookingCalendarControllerTest do
  use CozyCheckoutWeb.ConnCase

  test "GET /calendar/bookings.ics returns a protected iCalendar feed", %{conn: conn} do
    conn = get(conn, "/calendar/bookings.ics?token=test-booking-calendar-token")

    assert response(conn, 200) =~ "BEGIN:VCALENDAR\r\n"
    assert get_resp_header(conn, "content-type") == ["text/calendar; charset=utf-8"]
  end

  test "GET /calendar/bookings.ics rejects requests without the token", %{conn: conn} do
    conn = get(conn, "/calendar/bookings.ics")

    assert response(conn, 404) == "Not found"
  end
end
