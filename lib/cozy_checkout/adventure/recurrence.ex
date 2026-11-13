defmodule CozyCheckout.Adventure.Recurrence do
  @moduledoc "Calendar scheduling in Prague local dates; never measures a day as 86,400 seconds."

  @calendar_intervals %{"monthly" => 1, "semiannual" => 6, "yearly" => 12}

  def next(template, date) do
    date = max_date(template.starts_on, date)

    case template.cadence do
      "daily" ->
        date

      "once" ->
        template.starts_on

      cadence when cadence in ["monthly", "semiannual", "yearly"] ->
        calendar_date(template, date, :next)

      "weekly" ->
        Enum.find(
          Enum.map(0..6, &Date.add(date, &1)),
          &(Date.day_of_week(&1) in template.weekdays)
        )
    end
  end

  def latest(template, date) do
    candidate =
      case template.cadence do
        "daily" ->
          date

        "once" ->
          template.starts_on

        cadence when cadence in ["monthly", "semiannual", "yearly"] ->
          calendar_date(template, date, :latest)

        "weekly" ->
          Enum.find(
            Enum.map(0..6, &Date.add(date, -&1)),
            &(Date.day_of_week(&1) in template.weekdays)
          )
      end

    if candidate && Date.compare(candidate, template.starts_on) != :lt &&
         Date.compare(candidate, date) != :gt,
       do: candidate
  end

  # Always calculate from the original day; February must not move a 31st to the 28th forever.
  defp calendar_date(template, date, direction) do
    anchor = template.starts_on
    interval = Map.fetch!(@calendar_intervals, template.cadence)
    months = (date.year - anchor.year) * 12 + date.month - anchor.month
    index = div(max(months, 0), interval)
    candidate = anniversary(anchor, index * interval)

    case {direction, Date.compare(candidate, date)} do
      {:next, :lt} -> anniversary(anchor, (index + 1) * interval)
      {:latest, :gt} when index == 0 -> nil
      {:latest, :gt} -> anniversary(anchor, (index - 1) * interval)
      _ -> candidate
    end
  end

  defp anniversary(anchor, months) do
    absolute_month = anchor.year * 12 + anchor.month - 1 + months
    first = Date.new!(div(absolute_month, 12), rem(absolute_month, 12) + 1, 1)
    Date.new!(first.year, first.month, min(anchor.day, Date.days_in_month(first)))
  end

  def period(template, date) do
    cond do
      template.cadence == "once" ->
        "once"

      template.legacy_code && template.cadence == "weekly" ->
        "week:" <> Date.to_iso8601(Date.beginning_of_week(date))

      true ->
        "date:" <> Date.to_iso8601(date)
    end
  end

  def max_date(a, b), do: if(Date.compare(a, b) == :lt, do: b, else: a)
end
