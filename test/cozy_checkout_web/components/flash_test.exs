defmodule CozyCheckoutWeb.FlashTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias CozyCheckoutWeb.{CoreComponents, Layouts}

  test "success, information and errors have distinct semantic colors and icons" do
    html =
      render_component(&Layouts.flash_group/1,
        flash: %{"success" => "Uloženo", "info" => "Informace", "error" => "Chyba"}
      )
      |> LazyHTML.from_fragment()

    for {kind, color, icon, role} <- [
          {"success", "emerald", "check-circle", "status"},
          {"info", "blue", "information-circle", "status"},
          {"error", "red", "exclamation-circle", "alert"}
        ] do
      assert Enum.count(LazyHTML.query(html, "#flash-#{kind}[role='#{role}'] .bg-#{color}-50")) ==
               1

      assert Enum.count(LazyHTML.query(html, "#flash-#{kind} .hero-#{icon}")) == 1
      assert Enum.count(LazyHTML.query(html, "#flash-#{kind} button[aria-label]")) == 1
      assert Enum.count(LazyHTML.query(html, "#flash-#{kind}[phx-hook='Flash']")) == 1
    end

    for id <- ["client-error", "server-error"] do
      assert Enum.count(LazyHTML.query(html, "##{id}[phx-hook]")) == 0
    end
  end

  test "an existing success override retains its green styling" do
    html =
      render_component(&CoreComponents.flash/1,
        kind: :info,
        flash: %{"info" => "Restocked"},
        info_class: "alert-success"
      )
      |> LazyHTML.from_fragment()

    assert Enum.count(LazyHTML.query(html, "#flash-info .bg-emerald-50")) == 1
  end
end
