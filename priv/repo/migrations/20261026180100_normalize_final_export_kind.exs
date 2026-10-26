defmodule CozyCheckout.Repo.Migrations.NormalizeFinalExportKind do
  use Ecto.Migration

  def up do
    execute """
    UPDATE accommodation_abra_exports AS export
    SET verification = jsonb_set(export.verification, '{kind}', '"final"'::jsonb)
    FROM billing_documents AS document
    WHERE export.document_id = document.id
      AND document.kind = 'final'
      AND export.verification->>'kind' IS DISTINCT FROM 'final'
      AND jsonb_typeof(export.verification->'sources') = 'array'
      AND jsonb_typeof(export.verification->'expected') = 'object'
    """
  end

  # Operational routing normalization has no inverse; financial payloads are untouched.
  def down, do: :ok
end
