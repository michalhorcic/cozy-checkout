defmodule CozyCheckout.Repo.Migrations.CreateBookingBilling do
  use Ecto.Migration

  def change do
    alter table(:booking_invoices) do
      add :pricing_basis, :string, null: false, default: "legacy_net"
      add :priced_on, :date
    end

    alter table(:booking_invoice_items) do
      modify :price_per_night, :decimal, null: true, from: {:decimal, null: false}
      add :tax_mode, :string, null: false, default: "taxable"
    end

    create table(:billing_seasons, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :text, null: false
      add :valid_from, :date, null: false
      add :valid_to, :date, null: false
      add :adult, :decimal, precision: 14, scale: 2, null: false
      add :infant, :decimal, precision: 14, scale: 2, null: false
      add :child, :decimal, precision: 14, scale: 2, null: false
      add :vat_rate, :decimal, precision: 5, scale: 2, null: false, default: 12
      add :deleted_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:billing_seasons, [:deleted_at])
    create constraint(:billing_seasons, :valid_dates, check: "valid_to >= valid_from")
    # A GiST exclusion on the date range also protects concurrent season creation.
    execute "ALTER TABLE billing_seasons ADD CONSTRAINT billing_seasons_no_overlap EXCLUDE USING gist (daterange(valid_from, valid_to, '[]') WITH &&) WHERE (deleted_at IS NULL)",
            "ALTER TABLE billing_seasons DROP CONSTRAINT billing_seasons_no_overlap"

    create table(:billing_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :singleton, :boolean, null: false, default: true
      add :data, :map, null: false, default: %{}
      timestamps(type: :utc_datetime)
    end

    create unique_index(:billing_profiles, [:singleton])

    create table(:billing_customers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :booking_id, references(:bookings, type: :binary_id), null: false
      add :data, :map, null: false, default: %{}
      timestamps(type: :utc_datetime)
    end

    create unique_index(:billing_customers, [:booking_id])

    create table(:billing_series, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :string, null: false
      add :year, :integer, null: false
      add :prefix, :string, null: false
      add :digits, :integer, null: false, default: 5
      add :next_number, :integer, null: false, default: 1
      timestamps(type: :utc_datetime)
    end

    create unique_index(:billing_series, [:kind, :year])

    execute "CREATE SEQUENCE billing_variable_symbols START 1000000000 MAXVALUE 9999999999 NO CYCLE",
            "DROP SEQUENCE billing_variable_symbols"

    create table(:billing_documents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :booking_id, references(:bookings, type: :binary_id), null: false
      add :kind, :string, null: false
      add :number, :string, null: false
      add :variable_symbol, :string, null: false
      add :request_id, :uuid, null: false
      add :parent_id, references(:billing_documents, type: :binary_id)
      add :issued_on, :date, null: false
      add :tax_date, :date, null: false
      add :due_on, :date, null: false
      add :snapshot, :map, null: false
      add :lines, {:array, :map}, null: false, default: []
      add :total, :decimal, precision: 14, scale: 2, null: false
      add :pdf, :binary
      add :pdf_sha256, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:billing_documents, [:number])
    create unique_index(:billing_documents, [:variable_symbol])
    create unique_index(:billing_documents, [:request_id])

    create unique_index(:billing_documents, [:booking_id],
             where: "kind = 'final'",
             name: :billing_one_final
           )

    create index(:billing_documents, [:parent_id])
    create index(:billing_documents, [:booking_id])

    create table(:billing_payments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :booking_id, references(:bookings, type: :binary_id), null: false
      add :document_id, references(:billing_documents, type: :binary_id)
      add :tax_document_id, references(:billing_documents, type: :binary_id)
      add :request_id, :uuid, null: false
      add :kind, :string, null: false
      add :amount, :decimal, precision: 14, scale: 2, null: false
      add :paid_on, :date, null: false
      add :method, :string, null: false
      add :reference, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:billing_payments, [:request_id])
    create index(:billing_payments, [:booking_id])
    create index(:billing_payments, [:document_id])
    create unique_index(:billing_payments, [:tax_document_id])
    create constraint(:billing_payments, :positive_amount, check: "amount > 0")

    create table(:billing_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :document_id, references(:billing_documents, type: :binary_id), null: false
      add :request_id, :uuid, null: false
      add :recipient, :text, null: false
      add :subject, :text, null: false
      add :body, :text, null: false
      add :consented_at, :utc_datetime, null: false
      add :state, :string, null: false, default: "queued"
      add :attempts, :integer, null: false, default: 0
      add :error, :text
      add :accepted_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:billing_deliveries, [:request_id])
    create index(:billing_deliveries, [:document_id])
  end
end
