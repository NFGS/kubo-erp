defmodule KuboErp.Repo.Migrations.AddTenantToSaleItems do
  use Ecto.Migration

  @moduledoc """
  Denormaliza `tenant_id` en `sale_items`.

  La politica anterior resolvia el negocio con una subconsulta a `sales`
  (`sale_id IN (SELECT id FROM sales WHERE tenant_id = ...)`). Bajo carga
  concurrente esa subconsulta fallo de forma intermitente al insertar la linea
  de venta, y ademas obliga a PostgreSQL a evaluar RLS dos veces por fila. Con
  la columna propia, la politica es la misma comparacion por indice que usan
  `sales`, `products` y `stock_movements`.
  """

  @tenant "NULLIF(current_setting('app.tenant_id', true), '')::uuid"

  def up do
    execute("ALTER TABLE sale_items ADD COLUMN tenant_id uuid")

    # El relleno corre como dueno sin FORCE en AMBAS tablas: necesita ver todas
    # las filas de `sale_items` y tambien las de `sales` para copiar el negocio.
    execute("ALTER TABLE sale_items NO FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE sales NO FORCE ROW LEVEL SECURITY")

    execute("""
    UPDATE sale_items
    SET tenant_id = sales.tenant_id
    FROM sales
    WHERE sale_items.sale_id = sales.id
    """)

    execute("ALTER TABLE sales FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE sale_items ALTER COLUMN tenant_id SET NOT NULL")
    execute("DROP POLICY IF EXISTS sale_items_tenant_isolation ON sale_items")

    execute("""
    CREATE POLICY sale_items_tenant_isolation ON sale_items
      USING (tenant_id = #{@tenant})
      WITH CHECK (tenant_id = #{@tenant})
    """)

    execute("ALTER TABLE sale_items FORCE ROW LEVEL SECURITY")
    execute("CREATE INDEX idx_sale_items_tenant ON sale_items (tenant_id)")
  end

  def down do
    execute("DROP INDEX IF EXISTS idx_sale_items_tenant")
    execute("DROP POLICY IF EXISTS sale_items_tenant_isolation ON sale_items")
    execute("ALTER TABLE sale_items NO FORCE ROW LEVEL SECURITY")

    execute("""
    CREATE POLICY sale_items_tenant_isolation ON sale_items
      USING (sale_id IN (SELECT id FROM sales WHERE tenant_id = #{@tenant}))
      WITH CHECK (sale_id IN (SELECT id FROM sales WHERE tenant_id = #{@tenant}))
    """)

    execute("ALTER TABLE sale_items FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE sale_items DROP COLUMN tenant_id")
  end
end
