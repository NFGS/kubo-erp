defmodule KuboErp.Repo.Migrations.PurchaseWarehouse do
  @moduledoc """
  La compra recuerda a que bodega entro la mercancia (P-22, ADR-0016): antes
  todo entraba a la bodega por defecto y la anulacion revertia alli, aunque el
  negocio tuviera varias bodegas.

  El backfill corre con `FORCE` suspendido, como la migracion de bodegas: sin el
  contexto de negocio el dueno veria cero filas.
  """

  use Ecto.Migration

  def up do
    alter table(:purchases) do
      add(:warehouse_id, :binary_id)
    end

    # El backfill tambien lee `warehouses`, que tiene FORCE RLS: sin suspenderla
    # el join veria cero bodegas y el NOT NULL fallaria.
    execute("ALTER TABLE purchases NO FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE warehouses NO FORCE ROW LEVEL SECURITY")

    # Las compras historicas entraron a la bodega por defecto del negocio.
    execute("""
    UPDATE purchases p
    SET warehouse_id = w.id
    FROM warehouses w
    WHERE w.tenant_id = p.tenant_id
      AND w.is_default
      AND p.warehouse_id IS NULL
    """)

    # Respaldo: un negocio sin bodega por defecto (no deberia pasar; la
    # migracion de bodegas crea una) cae a su primera bodega.
    execute("""
    UPDATE purchases p
    SET warehouse_id = (
      SELECT w.id FROM warehouses w
      WHERE w.tenant_id = p.tenant_id
      ORDER BY w.is_default DESC, w.inserted_at
      LIMIT 1
    )
    WHERE p.warehouse_id IS NULL
    """)

    execute("ALTER TABLE warehouses FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE purchases FORCE ROW LEVEL SECURITY")

    alter table(:purchases) do
      modify(:warehouse_id, :binary_id, null: false)
    end

    create(index(:purchases, [:tenant_id, :warehouse_id]))
  end

  def down do
    alter table(:purchases) do
      remove(:warehouse_id)
    end
  end
end
