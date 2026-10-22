defmodule CozyCheckoutWeb.BillingLive.Helpers do
  def error(%Ecto.Changeset{} = cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, text ->
        String.replace(text, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end

  def error(value) when is_binary(value), do: value
  def error(_), do: "Operaci se nepodařilo dokončit. Zkontrolujte zadané údaje."
end
