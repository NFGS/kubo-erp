defmodule KuboErp.Repo.Migrations.CreateCreditNotes do
  use Ecto.Migration

  @moduledoc """
  Nota credito electronica (P-18, ADR-0014).

  Una factura es inmutable: anularla no es editarla, es emitir un documento
  nuevo que la referencia. La nota credito guarda su representacion emitida
  (CUDE y XML) por la misma razon que la factura.
  """

  def change do
    create table(:credit_notes, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, :binary_id, null: false)
      add(:sale_id, :binary_id, null: false)
      add(:invoice_id, :binary_id, null: false)
      add(:number, :string, null: false, size: 40)
      add(:cude, :string, null: false, size: 120)
      add(:qr_url, :string, null: false, size: 300)
      add(:reason, :string, null: false, size: 300)
      add(:provider, :string, null: false, size: 40)
      add(:xml, :text, null: false)
      add(:issued_at, :utc_datetime, null: false)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:credit_notes, [:tenant_id, :sale_id], name: :credit_notes_tenant_sale_unique))
    create(unique_index(:credit_notes, [:tenant_id, :number], name: :credit_notes_tenant_number_unique))

    # RLS: la nota credito pertenece al negocio igual que la venta (ADR-0010).
    execute("ALTER TABLE credit_notes ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE credit_notes FORCE ROW LEVEL SECURITY")

    execute("""
    CREATE POLICY credit_notes_tenant_isolation ON credit_notes
      USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
      WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
    """)
  end
end
