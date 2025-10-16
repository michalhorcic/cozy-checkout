defmodule CozyCheckout.IcalImporter do
  @moduledoc """
  Imports iCal files to create guests and bookings.
  """

  import Ecto.Query

  alias CozyCheckout.{Guests, Bookings, Repo}
  alias CozyCheckout.Guests.Guest
  alias CozyCheckout.Bookings.Booking

  @doc """
  Imports bookings from an iCal file content.
  Returns {:ok, stats} or {:error, reason}
  """
  def import_ical(file_content) do
    with {:ok, events} <- parse_ical(file_content),
         {:ok, stats} <- process_events(events) do
      {:ok, stats}
    end
  end

  defp parse_ical(content) do
    try do
      events =
        content
        |> String.split("BEGIN:VEVENT")
        |> Enum.drop(1)
        |> Enum.map(&parse_event/1)
        |> Enum.reject(&is_nil/1)

      {:ok, events}
    rescue
      e -> {:error, "Failed to parse iCal file: #{Exception.message(e)}"}
    end
  end

  defp parse_event(event_text) do
    summary = extract_field(event_text, "SUMMARY")
    dtstart = extract_field(event_text, "DTSTART")
    dtend = extract_field(event_text, "DTEND")
    description = extract_field(event_text, "Description")
    status = extract_field(event_text, "STATUS")

    # Parse description for contact info
    {phone, email, notes} = parse_description(description)

    if summary && dtstart && dtend do
      %{
        guest_name: summary,
        check_in_date: parse_date(dtstart),
        check_out_date: parse_date(dtend),
        phone: phone,
        email: email,
        notes: notes,
        status: map_status(status)
      }
    else
      nil
    end
  end

  defp extract_field(text, field_name) do
    case Regex.run(~r/#{field_name}:(.+)/, text) do
      [_, value] -> String.trim(value)
      _ -> nil
    end
  end

  defp parse_description(nil), do: {nil, nil, nil}

  defp parse_description(desc) do
    # Unescape the description (iCal uses \, and \n for escaping)
    desc = desc |> String.replace("\\,", ",") |> String.replace("\\n", "\n")

    phone = extract_description_field(desc, "Telefon")
    email = extract_description_field(desc, "Email")

    # Extract notes (everything after the adults/children count)
    notes =
      case Regex.run(~r/Dospělí:.*?děti \d+\\n(.+)$/s, desc) do
        [_, note] -> String.trim(note)
        _ -> nil
      end

    {phone, email, notes}
  end

  defp extract_description_field(desc, field) do
    case Regex.run(~r/#{field}: ?([^\n\\]+)/, desc) do
      [_, value] ->
        value = String.trim(value)
        if value == "" or value == "\\", do: nil, else: value

      _ ->
        nil
    end
  end

  defp parse_date(date_str) do
    # Format: 20251205T140000
    case Regex.run(~r/(\d{4})(\d{2})(\d{2})/, date_str) do
      [_, year, month, day] ->
        Date.new!(String.to_integer(year), String.to_integer(month), String.to_integer(day))

      _ ->
        nil
    end
  end

  defp map_status("CONFIRMED"), do: "active"
  defp map_status("TENTATIVE"), do: "upcoming"
  defp map_status(_), do: "upcoming"

  defp process_events(events) do
    stats = %{
      guests_created: 0,
      guests_found: 0,
      bookings_created: 0,
      bookings_skipped: 0,
      errors: []
    }

    result =
      Enum.reduce(events, stats, fn event, acc ->
        process_event(event, acc)
      end)

    {:ok, result}
  end

  defp process_event(event, stats) do
    case find_or_create_guest(event) do
      {:ok, guest, created?} ->
        stats =
          if created? do
            Map.update!(stats, :guests_created, &(&1 + 1))
          else
            Map.update!(stats, :guests_found, &(&1 + 1))
          end

        case create_booking(guest, event) do
          {:ok, _booking} ->
            Map.update!(stats, :bookings_created, &(&1 + 1))

          {:error, reason} ->
            stats
            |> Map.update!(:bookings_skipped, &(&1 + 1))
            |> Map.update!(:errors, &[{event.guest_name, reason} | &1])
        end

      {:error, reason} ->
        stats
        |> Map.update!(:bookings_skipped, &(&1 + 1))
        |> Map.update!(:errors, &[{event.guest_name, reason} | &1])
    end
  end

  defp find_or_create_guest(event) do
    # Try to find existing guest by name or email
    guest =
      cond do
        event.email && event.email != "" ->
          Repo.get_by(Guest, email: event.email) |> Repo.preload(:bookings)

        true ->
          Guest
          |> Ecto.Query.where([g], g.name == ^event.guest_name)
          |> Ecto.Query.where([g], is_nil(g.deleted_at))
          |> Repo.one()
          |> case do
            nil -> nil
            g -> Repo.preload(g, :bookings)
          end
      end

    case guest do
      nil ->
        # Create new guest
        case Guests.create_guest(%{
               name: event.guest_name,
               email: event.email,
               phone: event.phone
             }) do
          {:ok, guest} -> {:ok, guest, true}
          {:error, changeset} -> {:error, "Failed to create guest: #{inspect(changeset.errors)}"}
        end

      existing_guest ->
        {:ok, existing_guest, false}
    end
  end

  defp create_booking(guest, event) do
    # Check if booking already exists for this guest and dates
    existing =
      Booking
      |> Ecto.Query.where([b], b.guest_id == ^guest.id)
      |> Ecto.Query.where([b], b.check_in_date == ^event.check_in_date)
      |> Ecto.Query.where([b], is_nil(b.deleted_at))
      |> Repo.one()

    case existing do
      nil ->
        Bookings.create_booking(%{
          guest_id: guest.id,
          check_in_date: event.check_in_date,
          check_out_date: event.check_out_date,
          status: event.status,
          notes: event.notes
        })

      _existing ->
        {:error, "Booking already exists for these dates"}
    end
  end
end
