defmodule CozyCheckout.Adventure.Catalog do
  @moduledoc "Versioned game definitions. An activated quest keeps its own immutable snapshot."
  @quests [
    %{
      code: "prepare_stay",
      version: 1,
      title: "Připravit další pobyt",
      xp: 50,
      cadence: "weekly"
    },
    %{
      code: "review_deposits",
      version: 1,
      title: "Zkontrolovat otevřené zálohy",
      xp: 50,
      cadence: "weekly"
    },
    %{
      code: "shopping_plan",
      version: 1,
      title: "Dokončit týdenní nákupní plán",
      xp: 100,
      cadence: "weekly"
    },
    %{
      code: "improvement",
      version: 1,
      title: "Zavést jedno provozní zlepšení",
      xp: 250,
      cadence: "once"
    }
  ]

  def quests, do: @quests
  def fetch(code), do: Enum.find(@quests, &(&1.code == code))
end
