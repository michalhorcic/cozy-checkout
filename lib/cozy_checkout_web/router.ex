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

    live "/", MainMenuLive
  end

  # Admin section - CRUD interfaces for managing the system
  scope "/admin", CozyCheckoutWeb do
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
    live "/pricelists/management", PricelistLive.Management
    live "/pricelists/print", PricelistLive.Printable

    # Purchase Orders
    live "/purchase_orders", PurchaseOrderLive.Index, :index
    live "/purchase_orders/new", PurchaseOrderLive.Index, :new
    live "/purchase_orders/:id/edit", PurchaseOrderLive.Index, :edit
    live "/purchase_orders/:id", PurchaseOrderLive.Show

    # Stock Overview
    live "/stock", StockOverviewLive.Index

    # Stock Adjustments
    live "/stock-adjustments", StockAdjustmentLive.Index, :index
    live "/stock-adjustments/new", StockAdjustmentLive.Index, :new
    live "/stock-adjustments/:id/edit", StockAdjustmentLive.Index, :edit

    # Guests
    live "/guests", GuestLive.Index, :index
    live "/guests/new", GuestLive.Index, :new
    live "/guests/:id/edit", GuestLive.Index, :edit

    # Rooms
    live "/rooms", RoomLive.Index, :index
    live "/rooms/new", RoomLive.Index, :new
    live "/rooms/:id/edit", RoomLive.Index, :edit

    # Bookings
    live "/bookings", BookingLive.Index, :index
    live "/bookings/new", BookingLive.Index, :new
    live "/bookings/calendar", BookingLive.Calendar
    live "/bookings/:id", BookingLive.Show
    live "/bookings/:id/edit", BookingLive.Index, :edit
    live "/bookings/:booking_id/guests", BookingLive.ManageGuests

    # Orders
    live "/orders", OrderLive.Index, :index
    live "/orders/new", OrderLive.New
    live "/orders/:id/edit", OrderLive.Edit
    live "/orders/:id", OrderLive.Show
    live "/orders/:id/receipt", OrderLive.Receipt

    # Payments
    live "/payments", PaymentLive.Index, :index
    live "/payments/new", PaymentLive.New

    # Economy Management
    live "/economy", EconomyLive.Index

    # Statistics
    live "/statistics", StatisticsLive.Index

    # POHODA Export
    live "/pohoda-export", PohodaExportLive.Index, :index

    # iCal Import
    live "/ical-import", IcalImportLive.Index, :index

    # Meal Planner
    live "/meal-planner", MealPlannerLive.Index
    live "/meal-planner/templates", MealPlannerLive.Templates, :index
    live "/meal-planner/templates/new", MealPlannerLive.Templates, :new
    live "/meal-planner/templates/:id/edit", MealPlannerLive.Templates, :edit
    live "/meal-planner/print", MealPlannerLive.Print
  end

  # Point of Sale (POS) - Touch-friendly interface for bar staff
  scope "/pos", CozyCheckoutWeb.PosLive do
    pipe_through :browser

    live "/", GuestSelection
    live "/bookings/:booking_id/orders", OrderSelection
    live "/orders/:id", OrderManagement
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
