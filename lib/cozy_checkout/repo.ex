defmodule CozyCheckout.Repo do
  use Ecto.Repo,
    otp_app: :cozy_checkout,
    adapter: Ecto.Adapters.Postgres
end
