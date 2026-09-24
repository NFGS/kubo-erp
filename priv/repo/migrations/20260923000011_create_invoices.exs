defmodule KuboErp.Repo.Migrations.CreateInvoices do
  use Ecto.Migration

  @moduledoc """
  Factura electronica emitida para una venta (P-18, ADR-0014).

  Se guarda la representacion emitida (CUFE, XML) porque una factura es un
  documento inmutable: si se regenerara, el CUFE cambiaria y dejaria de
  coincidir con el que se entrego al cliente.
  """

  def change do
    create table(:invoices, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, :binary_id, null: false)
      add(:sale_id, :binary_id, null: false)
      add(:number, :string, null: false, size: 40)
      add(:cufe, :string, null: false, size: 120)
      add(:qr_url, :string, null: false, size: 300)
      add(:provider, :string, null: false, size: 40)
      add(:status, :string, null: false, size: 20, default: "ISSUED")
      add(:xml, :text, null: false)
      add(:issued_at, :utc_datetime, null: false)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:invoices, [:tenant_id, :sale_id], name: :invoices_tenant_sale_unique))
    create(unique_index(:invoices, [:tenant_id, :number], name: :invoices_tenant_number_unique))

    # RLS: la factura pertenece al negocio igual que la venta (ADR-0010).
    execute("ALTER TABLE invoices ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE invoices FORCE ROW LEVEL SECURITY")

    execute("""
    CREATE POLICY invoices_tenant_isolation ON invoices
      USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
      WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
    """)
  end
end
