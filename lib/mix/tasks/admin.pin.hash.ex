defmodule Mix.Tasks.Admin.Pin.Hash do
  use Mix.Task

  alias CozyCheckoutWeb.AdminAuth

  @shortdoc "Generate a PBKDF2 hash for ADMIN_PIN_HASH"

  @impl Mix.Task
  def run(_args) do
    pin = read_pin()

    if AdminAuth.valid_pin?(pin) do
      Mix.shell().info("ADMIN_PIN_HASH=#{AdminAuth.hash_pin(pin)}")
    else
      Mix.raise("PIN must contain 6 to 8 digits")
    end
  end

  defp read_pin do
    case :io.get_password(:standard_io) do
      pin when is_list(pin) ->
        List.to_string(pin)

      {:error, :enotsup} ->
        IO.write(:stderr, "This terminal cannot hide typed input; the PIN will be visible.\n")

        case IO.gets("Admin PIN (6 to 8 digits): ") do
          :eof -> Mix.raise("No PIN was entered")
          pin -> pin |> String.trim_trailing("\n") |> String.trim_trailing("\r")
        end

      _ ->
        Mix.raise("Could not read PIN from terminal")
    end
  end
end
