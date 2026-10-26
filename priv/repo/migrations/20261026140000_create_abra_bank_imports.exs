defmodule CozyCheckout.Repo.Migrations.CreateAbraBankImports do
  use Ecto.Migration

  def change do
    create table(:abra_bank_imports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :base_url, :text, null: false
      add :company_id, :text, null: false
      add :account, :text, null: false
      add :scan_id, :uuid
      add :offset, :integer, null: false, default: 0
      add :last_success_at, :utc_datetime
      add :last_attempt_at, :utc_datetime
      add :error, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:abra_bank_imports, [:base_url, :company_id, :account])

    create table(:abra_bank_movements, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :base_url, :text, null: false
      add :company_id, :text, null: false
      add :evidence, :text, null: false, default: "banka"
      add :remote_id, :text, null: false
      add :account, :text, null: false
      add :amount, :decimal, precision: 18, scale: 2, null: false
      add :currency, :text, null: false
      add :direction, :text, null: false
      add :paid_on, :date, null: false
      add :variable_symbol, :text
      add :counterparty, :text
      add :pairing, :string, null: false
      add :raw, :map, null: false
      add :scan_id, :uuid, null: false
      add :missing_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:abra_bank_movements, [:base_url, :company_id, :evidence, :remote_id],
             name: :abra_bank_movements_identity_index
           )

    create index(:abra_bank_movements, [:base_url, :company_id, :account])
  end
end
