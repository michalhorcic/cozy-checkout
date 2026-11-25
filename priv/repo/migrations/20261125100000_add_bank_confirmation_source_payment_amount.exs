defmodule CozyCheckout.Repo.Migrations.AddBankConfirmationSourcePaymentAmount do
  use Ecto.Migration

  def change do
    alter table(:abra_bank_confirmations) do
      add :source_payment_amount, :decimal, precision: 12, scale: 2
    end

    create constraint(:abra_bank_confirmations, :positive_source_payment_amount,
             check: "source_payment_amount IS NULL OR source_payment_amount > 0"
           )
  end
end
