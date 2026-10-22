defmodule CozyCheckout.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    pdf_options = [
      on_demand: true,
      no_sandbox: true,
      discard_stderr: Application.get_env(:cozy_checkout, :pdf_discard_stderr, true)
    ]

    pdf_options =
      case Application.get_env(:cozy_checkout, :chrome_executable) do
        nil -> pdf_options
        path -> Keyword.put(pdf_options, :chrome_executable, path)
      end

    children = [
      CozyCheckoutWeb.Telemetry,
      CozyCheckout.Repo,
      {Task.Supervisor, name: CozyCheckout.Billing.PdfTasks},
      {CozyCheckout.Billing.PdfBrowser, pdf_options},
      {DNSCluster, query: Application.get_env(:cozy_checkout, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: CozyCheckout.PubSub},
      CozyCheckoutWeb.AdminAuthRateLimiter,
      {Oban, Application.fetch_env!(:cozy_checkout, Oban)},
      # Start to serve requests, typically the last entry
      CozyCheckoutWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CozyCheckout.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CozyCheckoutWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
