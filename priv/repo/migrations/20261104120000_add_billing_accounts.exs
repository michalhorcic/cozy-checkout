defmodule CozyCheckout.Repo.Migrations.AddBillingAccounts do
  use Ecto.Migration

  def up do
    alter table(:bookings) do
      add :adults, :integer, null: false, default: 0
      add :infants, :integer, null: false, default: 0
      add :children, :integer, null: false, default: 0
      add :unclassified_guests, :integer, null: false, default: 0
      add :allocation_completed_at, :utc_datetime
      add :billing_pricing_template, :map
    end

    create constraint(:bookings, :nonnegative_guests,
             check: "adults >= 0 AND infants >= 0 AND children >= 0 AND unclassified_guests >= 0"
           )

    create table(:billing_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :booking_id, references(:bookings, type: :binary_id), null: false
      add :name, :text, null: false
      add :default, :boolean, null: false, default: false
      add :adults, :integer, null: false, default: 0
      add :infants, :integer, null: false, default: 0
      add :children, :integer, null: false, default: 0
      add :check_in_date, :date
      add :check_out_date, :date
      add :deleted_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:billing_accounts, [:booking_id],
             where: "\"default\"",
             name: :billing_default_account
           )

    create unique_index(:billing_accounts, [:id, :booking_id])

    create constraint(:billing_accounts, :nonnegative_guests,
             check: "adults >= 0 AND infants >= 0 AND children >= 0"
           )

    create constraint(:billing_accounts, :valid_dates,
             check:
               "check_out_date IS NULL OR check_in_date IS NULL OR check_out_date > check_in_date"
           )

    execute "UPDATE bookings SET allocation_completed_at = updated_at"

    # All historical rows, including deleted bookings, retain their original identities.
    execute """
    UPDATE bookings b SET
      adults = p.adults, infants = p.infants, children = p.children,
      unclassified_guests = p.unknown
    FROM (
      SELECT i.booking_id,
        COALESCE(SUM(x.quantity) FILTER (WHERE x.name = 'Dospělí'), 0) AS adults,
        COALESCE(SUM(x.quantity) FILTER (WHERE x.name = 'Děti do 2 let'), 0) AS infants,
        COALESCE(SUM(x.quantity) FILTER (WHERE x.name = 'Děti do 12 let'), 0) AS children,
        COALESCE(SUM(x.quantity) FILTER (WHERE x.name NOT IN ('Dospělí', 'Děti do 2 let', 'Děti do 12 let')), 0) AS unknown
      FROM booking_invoices i JOIN booking_invoice_items x ON x.booking_invoice_id = i.id
      WHERE x.item_type = 'person' GROUP BY i.booking_id
    ) p WHERE p.booking_id = b.id
    """

    execute """
    INSERT INTO billing_accounts (id, booking_id, name, "default", adults, infants, children, inserted_at, updated_at)
    SELECT gen_random_uuid(), b.id, COALESCE(NULLIF(c.data->>'name', ''), g.name, 'Výchozí plátce'), true,
      b.adults, b.infants, b.children, b.inserted_at, b.updated_at
    FROM bookings b LEFT JOIN guests g ON g.id = b.guest_id
      LEFT JOIN billing_customers c ON c.booking_id = b.id
    """

    for table <- [:booking_invoices, :billing_customers, :billing_documents, :billing_payments] do
      alter table(table) do
        add :billing_account_id, :binary_id
      end

      execute "UPDATE #{table} t SET billing_account_id = a.id FROM billing_accounts a WHERE a.booking_id = t.booking_id AND a.\"default\""

      alter table(table) do
        modify :billing_account_id, :binary_id, null: false
      end

      execute "ALTER TABLE #{table} ADD CONSTRAINT #{table}_account_owner FOREIGN KEY (billing_account_id, booking_id) REFERENCES billing_accounts(id, booking_id)"

      if table in [:billing_documents, :billing_payments],
        do: create(index(table, [:billing_account_id]))
    end

    drop unique_index(:booking_invoices, [:booking_id])
    drop unique_index(:billing_customers, [:booking_id])
    drop index(:billing_documents, [:booking_id], name: :billing_one_final)
    create unique_index(:booking_invoices, [:billing_account_id])
    create unique_index(:billing_customers, [:billing_account_id])

    create unique_index(:billing_documents, [:billing_account_id],
             where: "kind = 'final'",
             name: :billing_one_final
           )

    create unique_index(:billing_documents, [:id, :billing_account_id])

    execute "ALTER TABLE billing_documents ADD CONSTRAINT billing_parent_account FOREIGN KEY (parent_id, billing_account_id) REFERENCES billing_documents(id, billing_account_id)"

    execute "ALTER TABLE billing_payments ADD CONSTRAINT billing_payment_document_account FOREIGN KEY (document_id, billing_account_id) REFERENCES billing_documents(id, billing_account_id)"

    execute "ALTER TABLE billing_payments ADD CONSTRAINT billing_payment_tax_account FOREIGN KEY (tax_document_id, billing_account_id) REFERENCES billing_documents(id, billing_account_id)"

    execute """
    CREATE FUNCTION billing_guard_account_sources() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF TG_OP = 'UPDATE' AND (NEW.billing_account_id <> OLD.billing_account_id OR NEW.booking_id <> OLD.booking_id) THEN
        RAISE EXCEPTION 'Issued document ownership is immutable';
      END IF;
      IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(COALESCE(NEW.snapshot->'deductions', '[]'::jsonb)) deduction
        LEFT JOIN billing_documents source ON source.id = (deduction->>'source_document_id')::uuid
        WHERE source.id IS NULL OR source.kind <> 'tax_receipt' OR source.billing_account_id <> NEW.billing_account_id
      ) THEN
        RAISE EXCEPTION 'Deductions must reference tax receipts of the same billing account';
      END IF;
      RETURN NEW;
    END $$
    """

    execute "CREATE TRIGGER billing_account_sources BEFORE INSERT OR UPDATE OF billing_account_id, booking_id, snapshot ON billing_documents FOR EACH ROW EXECUTE FUNCTION billing_guard_account_sources()"
  end

  def down do
    raise "Multiple-payer accounting cannot be safely rolled back; restore a compatible backup/application."
  end
end
