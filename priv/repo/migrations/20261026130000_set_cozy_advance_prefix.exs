defmodule CozyCheckout.Repo.Migrations.SetCozyAdvancePrefix do
  use Ecto.Migration

  def up do
    # Keep the counter and all issued documents; only future numbers use the new prefix.
    execute "UPDATE billing_series SET prefix = 'COZY-ZF' WHERE kind = 'advance'"
  end

  # Do not roll numbering back after documents have used the new prefix.
  def down, do: :ok
end
