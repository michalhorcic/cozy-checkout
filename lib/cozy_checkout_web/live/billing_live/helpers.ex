defmodule CozyCheckoutWeb.BillingLive.Helpers do
  def email_defaults(document) do
    %{
      "request_id" => Ecto.UUID.generate(),
      "recipient" => document.snapshot["customer"]["email"] || "",
      "subject" => "#{CozyCheckout.Billing.kind_label(document.kind)} #{document.number}",
      "body" => "Dobrý den,\n\nv příloze zasíláme doklad k Vašemu pobytu.\n\nJindřichův dům",
      "consent" => "false"
    }
  end

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
