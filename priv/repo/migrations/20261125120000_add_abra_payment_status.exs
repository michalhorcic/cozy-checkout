defmodule CozyCheckout.Repo.Migrations.AddAbraPaymentStatus do
  use Ecto.Migration

  def change do
    alter table(:accommodation_abra_exports) do
      add :payment_total, :decimal, precision: 16, scale: 2
      add :payment_remaining, :decimal, precision: 16, scale: 2
      add :payment_checked_at, :utc_datetime_usec
      add :payment_attempted_at, :utc_datetime_usec
      add :payment_error, :text
    end
  end
end
