ExUnit.start()

# Never send accounting requests from a test to the real ABRA server.
Req.default_options(plug: {Req.Test, CozyCheckout.Abra.Client})
# Disable background processing in the test instance before enabling Sandbox.
# Keep testing mode disabled because the installed Oban requires newer migrations
# in manual mode; no application configuration or schema is changed here.
:ok = Supervisor.terminate_child(CozyCheckout.Supervisor, Oban)
:ok = Supervisor.delete_child(CozyCheckout.Supervisor, Oban)

oban_options =
  Application.fetch_env!(:cozy_checkout, Oban)
  |> Keyword.merge(
    queues: false,
    plugins: false,
    peer: {Oban.Peers.Isolated, [leader?: false]},
    notifier: Oban.Notifiers.Isolated,
    stage_interval: :infinity
  )

{:ok, _} = Supervisor.start_child(CozyCheckout.Supervisor, {Oban, oban_options})

Ecto.Adapters.SQL.Sandbox.mode(CozyCheckout.Repo, :manual)
