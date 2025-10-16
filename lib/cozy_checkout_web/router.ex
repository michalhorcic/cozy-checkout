defmodule CozyCheckoutWeb.Router do
  use CozyCheckoutWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CozyCheckoutWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", CozyCheckoutWeb do
    pipe_through :browser

    live "/", DashboardLive

    # Categories
    live "/categories", CategoryLive.Index, :index
    live "/categories/new", CategoryLive.Index, :new
    live "/categories/:id/edit", CategoryLive.Index, :edit

    # Products
    live "/products", ProductLive.Index, :index
    live "/products/new", ProductLive.Index, :new
    live "/products/:id/edit", ProductLive.Index, :edit

    # Pricelists
    live "/pricelists", PricelistLive.Index, :index
    live "/pricelists/new", PricelistLive.Index, :new
    live "/pricelists/:id/edit", PricelistLive.Index, :edit

    # Guests
    live "/guests", GuestLive.Index, :index
    live "/guests/new", GuestLive.Index, :new
    live "/guests/:id/edit", GuestLive.Index, :edit

    # Orders
    live "/orders", OrderLive.Index, :index
    live "/orders/new", OrderLive.New
    live "/orders/:id", OrderLive.Show

    # Payments
    live "/payments", PaymentLive.Index, :index
    live "/payments/new", PaymentLive.New
  end

  # Other scopes may use custom stacks.
  # scope "/api", CozyCheckoutWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:cozy_checkout, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CozyCheckoutWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
