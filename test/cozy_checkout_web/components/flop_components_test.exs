defmodule CozyCheckoutWeb.FlopComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias CozyCheckout.Sales.Order
  alias CozyCheckoutWeb.FlopComponents

  test "pagination renders the next link when the default order limit is exceeded" do
    assert {:ok, flop} = Flop.validate(%{}, for: Order)
    assert flop.limit == 100
    assert flop.page == nil

    meta = meta(flop, 1)

    html =
      render_component(&FlopComponents.pagination/1, meta: meta, path: "/admin/orders")
      |> LazyHTML.from_fragment()

    links = LazyHTML.attribute(LazyHTML.query(html, "a"), "href")

    assert Enum.any?(links, fn link ->
             params = query_params(link)
             params["page"] == "2" and params["page_size"] == "100"
           end)
  end

  test "offset navigation preserves the current page, page size, filters and sorting" do
    flop = %Flop{
      limit: 100,
      offset: 100,
      filters: [%Flop.Filter{field: :status, op: :==, value: "open"}],
      order_by: [:inserted_at],
      order_directions: [:desc]
    }

    for {action, target, expected_page} <- [
          {:next, nil, "3"},
          {:previous, nil, "1"},
          {:page, 3, "3"},
          {:order, :order_number, "2"}
        ] do
      params =
        FlopComponents.build_path("/admin/orders", meta(flop, 2), action, target)
        |> query_params()

      assert params["page"] == expected_page
      assert params["page_size"] == "100"
      assert params["filters"]["0"]["value"] == "open"
      assert {:ok, _} = Flop.validate(params, for: Order)

      if action == :order do
        assert hd(params["order_by"]) == "order_number"
      else
        assert params["order_by"] == ["inserted_at"]
      end
    end
  end

  test "raw custom filters survive navigation without conflicting pagination parameters" do
    raw_params = %{
      "limit" => "100",
      "offset" => "100",
      "filters" => %{
        "0" => %{"field" => "guest_name", "op" => "ilike", "value" => "Novák"},
        "1" => %{"field" => "payment_method", "op" => "==", "value" => "cash"}
      }
    }

    params =
      FlopComponents.build_path(
        "/admin/orders",
        meta(%Flop{limit: 100, offset: 100}, 2),
        :next,
        nil,
        raw_params
      )
      |> query_params()

    assert params["page"] == "3"
    assert params["page_size"] == "100"
    assert params["filters"] == raw_params["filters"]
    refute Map.has_key?(params, "limit")
    refute Map.has_key?(params, "offset")
  end

  test "page-based navigation keeps its current page size" do
    meta = meta(%Flop{page: 2, page_size: 25}, 2)

    for {action, expected_page} <- [{:next, "3"}, {:previous, "1"}] do
      params = FlopComponents.build_path("/admin/orders", meta, action) |> query_params()
      assert params["page"] == expected_page
      assert params["page_size"] == "25"
    end
  end

  defp meta(flop, page) do
    %Flop.Meta{
      flop: flop,
      current_page: page,
      current_offset: (page - 1) * (flop.page_size || flop.limit),
      page_size: flop.page_size || flop.limit,
      total_count: 250,
      total_pages: 3,
      has_previous_page?: page > 1,
      has_next_page?: page < 3
    }
  end

  defp query_params(path),
    do: path |> URI.parse() |> Map.fetch!(:query) |> Plug.Conn.Query.decode()
end
