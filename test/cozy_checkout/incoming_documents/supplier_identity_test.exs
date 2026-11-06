defmodule CozyCheckout.IncomingDocuments.SupplierIdentityTest do
  use ExUnit.Case, async: true
  alias CozyCheckout.IncomingDocuments.SupplierIdentity, as: Identity

  test "strict contract rejects unknown keys, types and unbounded output without atoms" do
    data = %{
      "name" => nil,
      "ic" => nil,
      "dic" => nil,
      "country_code" => nil,
      "ambiguous" => false,
      "uncertainties" => []
    }

    assert :ok = Identity.validate(data)

    for invalid <- [
          nil,
          %{},
          Map.put(data, "account", "321"),
          Map.put(data, "ic", 123),
          Map.put(data, "ambiguous", nil),
          Map.put(data, "uncertainties", [123]),
          Map.put(data, "name", String.duplicate("x", 2001))
        ] do
      assert {:error, _} = Identity.validate(invalid)
    end
  end

  test "Czech checksum preserves leading zeroes and never strips arbitrary characters" do
    assert Identity.normalize_ic("IČO: 00 006 947") == "00006947"
    assert Identity.valid_ic?("00006947")
    assert Identity.valid_ic?("64945880")

    for ic <- [nil, "64945881", "6494588", "649458800", "CZ64945880", "6494-5880"] do
      refute Identity.valid_ic?(ic)
    end

    assert Identity.normalize_ic("IČO: 6494-5880") == "6494-5880"
    identity = Identity.normalize(%{"ic" => nil, "dic" => "cz 1234567890"})
    assert identity["ic"] == nil
    assert identity["dic"] == "CZ1234567890"
  end
end
