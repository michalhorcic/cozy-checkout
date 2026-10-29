defmodule CozyCheckoutWeb.EconomicsChartsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias CozyCheckoutWeb.EconomicsLive.Charts

  test "Decimal scaling preserves zero and negative corrections without a minimum-height fake value" do
    assert Charts.scale("0", "0") == 0
    assert Charts.scale("0", "100") == 0
    assert Charts.scale("-1.25", "2.50") == 24
    assert Charts.maximum(["-200", "100"]) == "200"
  end

  test "signed monthly and cost charts expose exact amounts, status and account drilldowns" do
    report = %{
      period: %{"code" => "2026"},
      from: "2026-07",
      to: "2026-07",
      confirmations: [%{month: "2026-07-01", confirmed: false}],
      months: [
        %{
          "from" => "2026-07-01",
          "totals" => %{"revenue" => "0", "expense" => "100", "result" => "-100"}
        }
      ],
      cost_categories: [
        %{
          category: "Opravy nákladů",
          amount: "-100",
          accounts: [%{code: "511001", name: "Opravy", totals: %{"expense" => "-100"}}]
        }
      ]
    }

    monthly = render_component(&Charts.monthly/1, report: report)
    assert monthly =~ "Nepotvrzeno"
    assert monthly =~ "top: 50%; height: 48%"
    assert monthly =~ "height: 0%"
    assert monthly =~ "-100.00 CZK"
    costs = render_component(&Charts.costs/1, report: report)
    assert costs =~ "right: 50%; width: 48%"
    assert costs =~ "/admin/economics/accounts/511001"
    assert costs =~ "Opravy nákladů"
  end
end
