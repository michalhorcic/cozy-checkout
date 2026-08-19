# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :cozy_checkout,
  ecto_repos: [CozyCheckout.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :cozy_checkout, CozyCheckoutWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: CozyCheckoutWeb.ErrorHTML, json: CozyCheckoutWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: CozyCheckout.PubSub,
  live_view: [signing_salt: "P9lJliu/"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :cozy_checkout, CozyCheckout.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  cozy_checkout: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  cozy_checkout: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Flop
config :flop, repo: CozyCheckout.Repo

# POHODA Export Configuration
config :cozy_checkout,
  # Your company ICO (tax ID) - CHANGE THIS
  pohoda_ico: "23741457",
  # Default accounting account in POHODA - CHANGE THIS
  pohoda_default_account: "1",
  # Bank account for QR code payments - CHANGE THIS
  bank_account: "2903322739/2010"

# Oban background job processing
config :cozy_checkout, Oban,
  repo: CozyCheckout.Repo,
  queues: [abra_sync: 3]

# Abra Flexi REST API integration
config :cozy_checkout, :abra,
  base_url: System.get_env("ABRA_BASE_URL", "https://moruska.flexibee.eu"),
  company_id: System.get_env("ABRA_COMPANY_ID", "moruska_s_r_o__2026_08_19_1130_testovani_bar"),
  username: System.get_env("ABRA_USERNAME", ""),
  password: System.get_env("ABRA_PASSWORD", ""),
  cash_register_code: System.get_env("ABRA_CASH_REGISTER_CODE", "POKLADNA KČ"),
  document_series_code: System.get_env("ABRA_DOCUMENT_SERIES_CODE", "FAKTURA-BAR"),
  bank_account_code: System.get_env("ABRA_BANK_ACCOUNT_CODE", "BANKOVNÍ ÚČET")

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
