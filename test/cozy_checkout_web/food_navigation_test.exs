defmodule CozyCheckoutWeb.FoodNavigationTest do
  use ExUnit.Case, async: true
  alias CozyCheckoutWeb.FoodNavigation

  test "only valid bounded dates, UUIDs and known origins enter navigation links" do
    assert FoodNavigation.context(%{
             "from" => %{"invalid" => "shape"},
             "to" => "bad",
             "booking" => "no-uuid",
             "origin" => "https://example.com"
           }) == %{}

    assert FoodNavigation.context(%{"from" => "2027-01-10", "to" => "2027-01-08"}) == %{}
    assert FoodNavigation.context(%{"from" => "2027-01-01", "to" => "2028-01-02"}) == %{}

    assert FoodNavigation.back_path(%{"origin" => "https://example.com"}, "/admin/recipes") ==
             "/admin/recipes"
  end

  test "recipe calculation parameters survive adding a safe planning context" do
    booking = Ecto.UUID.generate()

    path =
      FoodNavigation.with_context("/admin/recipes/example?adults=10&children=5", %{
        "from" => "2027-01-08",
        "to" => "2027-01-10",
        "booking" => booking,
        "origin" => "shopping"
      })

    query = path |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["adults"] == "10"
    assert query["children"] == "5"
    assert query["booking"] == booking

    assert FoodNavigation.back_path(query, "/admin/recipes") ==
             FoodNavigation.path(:shopping, query)
  end
end
