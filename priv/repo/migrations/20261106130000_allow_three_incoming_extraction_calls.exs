defmodule CozyCheckout.Repo.Migrations.AllowThreeIncomingExtractionCalls do
  use Ecto.Migration

  def up do
    drop constraint(:incoming_documents, :incoming_extraction_attempts)

    create constraint(:incoming_documents, :incoming_extraction_attempts,
             check: "extraction_attempts BETWEEN 0 AND 3"
           )
  end

  def down do
    # Do not rewrite historical call counts; rollback fails if three-call runs exist.
    drop constraint(:incoming_documents, :incoming_extraction_attempts)

    create constraint(:incoming_documents, :incoming_extraction_attempts,
             check: "extraction_attempts BETWEEN 0 AND 2"
           )
  end
end
