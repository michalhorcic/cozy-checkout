defmodule CozyCheckout.Repo.Migrations.AddBankConfirmationKind do
  use Ecto.Migration

  def change do
    alter table(:abra_bank_confirmations) do
      add(:kind, :text, null: false, default: "advance")
    end

    create(
      constraint(:abra_bank_confirmations, :valid_bank_confirmation_kind,
        check: "kind IN ('advance', 'final')"
      )
    )
  end
end
