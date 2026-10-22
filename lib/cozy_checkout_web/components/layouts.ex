defmodule CozyCheckoutWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use CozyCheckoutWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :content_class, :string, default: "mx-auto max-w-2xl space-y-4"
  attr :main_class, :string, default: "px-4 py-20 sm:px-6 lg:px-8"
  attr :show_header, :boolean, default: false
  attr :flash_info_class, :string, default: nil
  attr :food_section, :atom, default: nil
  attr :food_context, :map, default: %{}

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <.admin_header :if={@show_header} />

    <div
      :if={@food_section}
      id="food-layout"
      class="food-layout min-h-screen bg-secondary-50 text-primary-500 lg:flex"
    >
      <aside
        id="food-sidebar"
        class="hidden h-dvh w-56 shrink-0 overflow-y-auto border-r border-secondary-200 bg-white lg:sticky lg:top-0 lg:block print:hidden"
      >
        <.food_navigation id="food-desktop" active={@food_section} context={@food_context} />
      </aside>
      <div class="min-w-0 flex-1">
        <details
          id="food-mobile-navigation"
          class="sticky top-0 z-40 border-b border-secondary-200 bg-white lg:hidden print:hidden"
          phx-window-keydown={JS.remove_attribute("open", to: "#food-mobile-navigation")}
          phx-key="Escape"
        >
          <summary class="flex cursor-pointer list-none items-center justify-between gap-3 px-4 py-4 text-sm font-semibold">
            <span class="flex items-center gap-3"><img
              src={~p"/images/cozy-knot.svg"}
              alt=""
              width="28"
              height="28"
            /><span>Stravování</span><.icon name="hero-bars-3" class="h-5 w-5 text-primary-400" /></span>
            <span class="text-tertiary-600">{food_label(@food_section)}</span>
          </summary>
          <div class="max-h-[75dvh] overflow-y-auto">
            <.food_navigation id="food-mobile" active={@food_section} context={@food_context} />
          </div>
        </details>
        <main id="food-main" class="mx-auto w-full max-w-7xl px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
          <nav
            aria-label="Drobečková navigace"
            class="mb-6 flex flex-wrap items-center gap-2 text-xs text-primary-400 print:hidden"
          >
            <.link navigate={~p"/admin"} class="text-tertiary-600 hover:underline">Administrace</.link>
            <span aria-hidden="true">/</span><.link
              navigate={CozyCheckoutWeb.FoodNavigation.path(:planner, @food_context)}
              class="text-tertiary-600 hover:underline"
            >Stravování</.link>
            <span aria-hidden="true">/</span><span aria-current="page">{food_label(@food_section)}</span>
          </nav>
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>
    <main :if={is_nil(@food_section)} class={@main_class}>
      <div class={@content_class}>{render_slot(@inner_block)}</div>
    </main>

    <.flash_group flash={@flash} info_class={@flash_info_class} />
    """
  end

  attr :id, :string, required: true
  attr :active, :atom, required: true
  attr :context, :map, required: true

  defp food_navigation(assigns) do
    assigns =
      assign(assigns, :groups, [
        {"Provoz",
         [
           {:planner, "Plán jídel", "hero-calendar-days"},
           {:shopping, "Nákup", "hero-shopping-cart"}
         ]},
        {"Knihovna",
         [
           {:variants, "Varianty menu", "hero-rectangle-stack"},
           {:recipes, "Recepty", "hero-book-open"},
           {:ingredients, "Suroviny", "hero-beaker"}
         ]},
        {"Nástroje",
         [
           {:templates, "Šablony textů jídel", "hero-document-duplicate"},
           {:settings, "Nastavení porcí", "hero-adjustments-horizontal"}
         ]}
      ])

    ~H"""
    <nav id={@id} aria-label="Stravování" class="p-4">
      <.link
        navigate={CozyCheckoutWeb.FoodNavigation.path(:planner, @context)}
        class="mb-6 hidden items-center gap-3 px-2 py-2 font-bold text-primary-500 lg:flex"
      >
        <img src={~p"/images/cozy-knot.svg"} alt="" width="28" height="28" class="shrink-0" />
        <span><span class="block text-sm">Cozy Checkout</span><span class="block text-xs font-normal text-primary-400">Stravování</span></span>
      </.link>
      <div :for={{label, entries} <- @groups} class="mb-5">
        <p class="mb-2 px-3 text-[11px] font-semibold uppercase tracking-wider text-primary-400">
          {label}
        </p>
        <.link
          :for={{section, title, icon} <- entries}
          id={"#{@id}-#{section}"}
          navigate={CozyCheckoutWeb.FoodNavigation.path(section, @context)}
          phx-click={JS.remove_attribute("open", to: "#food-mobile-navigation")}
          aria-current={@active == section && "page"}
          class={[
            "mb-1 flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm transition focus-visible:outline-2 focus-visible:outline-tertiary-500",
            if(@active == section,
              do: "bg-tertiary-100 font-semibold text-tertiary-800",
              else: "text-primary-500 hover:bg-secondary-50"
            )
          ]}
        >
          <.icon name={icon} class="h-4 w-4 shrink-0" />{title}
        </.link>
      </div>
      <.link
        navigate={~p"/admin"}
        class="mt-4 flex items-center gap-2 border-t border-secondary-200 px-3 pt-5 text-xs text-tertiary-600 hover:underline"
      >
        <.icon name="hero-arrow-left" class="h-4 w-4" />Zpět do administrace
      </.link>
    </nav>
    """
  end

  defp food_label(section),
    do:
      %{
        planner: "Plán jídel",
        shopping: "Nákup",
        variants: "Varianty menu",
        recipes: "Recepty",
        ingredients: "Suroviny",
        templates: "Šablony textů jídel",
        settings: "Nastavení porcí"
      }[section]

  @doc "Renders the shared internal header around authenticated admin pages."
  def admin(assigns) do
    ~H"""
    <.admin_header />
    {@inner_content}
    """
  end

  def admin_header(assigns) do
    ~H"""
    <header
      id="admin-brand-header"
      class="border-b border-secondary-200 bg-white px-4 py-3 sm:px-6 lg:px-8 print:hidden"
    >
      <div class="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-3">
        <.link
          navigate={~p"/admin"}
          class="inline-flex min-h-11 items-center gap-3 rounded-lg focus-visible:outline-2 focus-visible:outline-tertiary-500"
          aria-label="Cozy Checkout — administrace"
        >
          <img src={~p"/images/cozy-knot.svg"} alt="" width="32" height="32" class="shrink-0" />
          <span><span class="block text-sm font-semibold text-primary-500">Cozy Checkout</span><span class="block text-xs text-primary-400">Jindřichův dům</span></span>
        </.link>
        <.link
          navigate={~p"/pos"}
          class="inline-flex min-h-11 items-center gap-2 rounded-lg px-3 text-sm text-primary-400 transition-colors hover:bg-secondary-50 hover:text-primary-500 focus-visible:outline-2 focus-visible:outline-tertiary-500"
        >
          <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />Pokladna
        </.link>
      </div>
    </header>
    """
  end

  @doc """
  Renders the POS layout for touch-friendly interface.

  This layout is minimal and optimized for tablet/touch devices.

  ## Examples

      <Layouts.pos page_title={@page_title}>
        <h1>Content</h1>
      </Layouts.pos>

  """
  attr :page_title, :string, required: true
  slot :inner_block, required: true

  def pos(assigns) do
    ~H"""
    {render_slot(@inner_block)}
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"
  attr :info_class, :string, default: nil

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      aria-live="polite"
      class="pointer-events-none fixed right-4 top-4 z-50 flex w-[calc(100%-2rem)] max-w-sm flex-col gap-3"
    >
      <.flash kind={:success} flash={@flash} />
      <.flash kind={:info} flash={@flash} info_class={@info_class} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
