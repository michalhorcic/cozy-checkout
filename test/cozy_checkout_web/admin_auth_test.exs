defmodule CozyCheckoutWeb.AdminAuthTest do
  use ExUnit.Case, async: false

  alias CozyCheckoutWeb.{AdminAuth, AdminAuthRateLimiter}

  test "PIN hashes are salted and verify without storing the PIN" do
    previous_hash = Application.get_env(:cozy_checkout, :admin_pin_hash)
    on_exit(fn -> restore_pin_hash(previous_hash) end)

    hash = AdminAuth.hash_pin("482731")
    Application.put_env(:cozy_checkout, :admin_pin_hash, hash)

    assert AdminAuth.enabled?()
    assert AdminAuth.verify_pin("482731")
    refute AdminAuth.verify_pin("482732")
    refute AdminAuth.verify_pin("123")
  end

  test "an address is temporarily blocked after five wrong PINs" do
    address = {:test, self(), make_ref()}
    on_exit(fn -> AdminAuthRateLimiter.reset(address) end)

    for _attempt <- 1..5 do
      assert AdminAuthRateLimiter.allowed?(address)
      assert :ok = AdminAuthRateLimiter.record_failure(address)
    end

    refute AdminAuthRateLimiter.allowed?(address)
    assert :ok = AdminAuthRateLimiter.reset(address)
    assert AdminAuthRateLimiter.allowed?(address)
  end

  defp restore_pin_hash(nil), do: Application.delete_env(:cozy_checkout, :admin_pin_hash)

  defp restore_pin_hash(hash),
    do: Application.put_env(:cozy_checkout, :admin_pin_hash, hash)
end
