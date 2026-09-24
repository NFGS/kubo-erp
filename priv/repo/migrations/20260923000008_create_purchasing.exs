defmodule KuboErp.Repo.Migrations.CreatePurchasing do
  use Ecto.Migration

  @moduledoc """
  Compras y proveedores (P-15, Fase 3).

  Cierra el ciclo del inventario: la mercancia entra por una compra con su
  proveedor y su costo, no por un ajuste manual. La compra mueve el kardex
  (`reference_type = PURCHASE`), actualiza el costo del producto con el valor sin
  IVA y deja un evento en la bandeja de salida.

  RLS: `purchase_items` lleva `tenant_id` denormalizado (misma leccion que en
  `sale_items`: la politica por indice, no por subconsulta).
  """

  @tenant "NULLIF(current_setting('app.tenant_id', true), '')::uuid"

  def change do
    alter table(:tenant_counters) do
      add(:purchase_seq, :bigint, null: false, default: 0)
    end

    create table(:suppliers, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, :binary_id, null: false)
      add(:name, :string, size: 160, null: false)
      add(:tax_id, :string, size: 40)
      add(:contact_name, :string, size: 160)
      add(:phone, :string, size: 40)
      add(:email, :string, size: 180)
      add(:address, :string, size: 200)
      add(:notes, :string, size: 500)
      add(:active, :boolean, null: false, default: true)
      add(:deleted_at, :utc_datetime)

      timestamps(type: :utc_datetime)
    end

    create(index(:suppliers, [:tenant_id, :name]))

    create(
      unique_index(:suppliers, [:tenant_id, :tax_id],
        where: "tax_id IS NOT NULL AND deleted_at IS NULL",
        name: :suppliers_tenant_tax_id_unique
      )
    )

    create table(:purchases, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, :binary_id, null: false)
      add(:number, :string, size: 20, null: false)

      add(:supplier_id, references(:suppliers, type: :binary_id, on_delete: :restrict),
        null: false
      )

      # Copia del nombre: el historico no cambia si el proveedor se renombra.
      add(:supplier_name, :string, size: 160, null: false)

      add(:status, :string, size: 20, null: false, default: "RECEIVED")
      add(:subtotal, :decimal, precision: 14, scale: 2, null: false, default: 0)
      add(:tax, :decimal, precision: 14, scale: 2, null: false, default: 0)
      add(:total, :decimal, precision: 14, scale: 2, null: false, default: 0)
      add(:notes, :string, size: 400)
      add(:received_by, :binary_id)
      add(:received_at, :utc_datetime, null: false)
      add(:voided_at, :utc_datetime)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:purchases, [:tenant_id, :number]))
    create(index(:purchases, [:tenant_id, :received_at]))
    create(constraint(:purchases, :purchases_total_not_negative, check: "total >= 0"))

    create table(:purchase_items, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, :binary_id, null: false)

      add(:purchase_id, references(:purchases, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:product_id, references(:products, type: :binary_id, on_delete: :restrict), null: false)

      add(:product_name, :string, size: 160, null: false)
      add(:quantity, :integer, null: false)
      add(:unit_cost, :decimal, precision: 14, scale: 2, null: false)
      add(:tax_rate, :decimal, precision: 5, scale: 2, null: false, default: 19.00)
      add(:tax_amount, :decimal, precision: 14, scale: 2, null: false, default: 0)
      add(:total, :decimal, precision: 14, scale: 2, null: false)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create(index(:purchase_items, [:purchase_id]))
    create(index(:purchase_items, [:tenant_id]))
    create(constraint(:purchase_items, :purchase_items_quantity_positive, check: "quantity > 0"))

    for tabla <- ["suppliers", "purchases", "purchase_items"] do
      execute("ALTER TABLE #{tabla} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{tabla} FORCE ROW LEVEL SECURITY")
      execute("DROP POLICY IF EXISTS #{tabla}_tenant_isolation ON #{tabla}")

      execute("""
      CREATE POLICY #{tabla}_tenant_isolation ON #{tabla}
        USING (tenant_id = #{@tenant})
        WITH CHECK (tenant_id = #{@tenant})
      """)
    end
  end
end
