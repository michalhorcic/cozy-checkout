defmodule CozyCheckout.Sales.AccountStamps do
  @moduledoc "Stable, decorative identities for bar accounts."

  @stamps [
    {"fox", "Liška"},
    {"pinecone", "Šiška"},
    {"lantern", "Petrolejka"},
    {"mushroom", "Hříbek"},
    {"spruce", "Smrk"},
    {"key", "Klíč od chalupy"},
    {"moon", "Měsíc nad kopcem"},
    {"mug", "Hrnek s párou"}
  ]
  @keys Enum.map(@stamps, &elem(&1, 0))

  def all, do: @stamps
  def keys, do: @keys

  def key(%{account_stamp: stamp}) when stamp in @keys, do: stamp

  def key(%{id: id}) when is_binary(id) do
    <<seed::unsigned-32, _rest::binary>> = :crypto.hash(:sha256, id)
    Enum.at(@keys, rem(seed, length(@keys)))
  end

  def key(_order), do: hd(@keys)

  def label(key) do
    Enum.find_value(@stamps, fn {k, label} -> if k == key, do: label end)
  end

  def suggest(orders) do
    counts = Enum.frequencies_by(orders, &key/1)
    Enum.min_by(@keys, &Map.get(counts, &1, 0))
  end
end
