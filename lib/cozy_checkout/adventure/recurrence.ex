defmodule CozyCheckout.Adventure.Recurrence do
  @moduledoc "Calendar scheduling in Prague local dates; never measures a day as 86,400 seconds."

  def next(template, date) do
    date = max_date(template.starts_on, date)

    case template.cadence do
      "daily" ->
        date

      "once" ->
        template.starts_on

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
