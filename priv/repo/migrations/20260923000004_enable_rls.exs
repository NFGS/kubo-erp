defmodule KuboErp.Repo.Migrations.EnableRls do
  use Ecto.Migration

  @moduledoc """
  Row Level Security para las tablas de negocio del ERP (P-02).

  El aislamiento entre negocios deja de depender de que cada consulta recuerde
  filtrar: lo impone PostgreSQL. Cada peticion abre una transaccion y fija
  `app.tenant_id` con `set_config(..., true)`; sin esa variable no hay filas.

  `FORCE` es imprescindible: el rol de la aplicacion (kubo_erp) es el dueno de
  las tablas y, sin FORCE, PostgreSQL lo eximiria de las politicas.

  `sale_items` no tiene `tenant_id`: su politica hereda el negocio a traves de
  la venta. `outbox_events` queda fuera a proposito: es una tabla operativa que
  el publicador de barrido lee cruzando negocios para entregar los eventos.

  Nota: Ecto envia cada `execute/1` como una sentencia preparada, de modo que
  aqui se emite una sentencia por llamada (varias juntas fallan con
  "cannot insert multiple commands into a prepared statement").
  """

  @tenant "NULLIF(current_setting('app.tenant_id', true), '')::uuid"

  def up do
    tenant_table("products")
    tenant_table("stock_movements")
    tenant_table("sales")
    sale_items_table()
  end

  def down do
    disable("sale_items")
    disable("sales")
    disable("stock_movements")
    disable("products")
  end

  defp tenant_table(table) do
    execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    execute("DROP POLICY IF EXISTS #{table}_tenant_isolation ON #{table}")

    execute("""
    CREATE POLICY #{table}_tenant_isolation ON #{table}
      USING (tenant_id = #{@tenant})
      WITH CHECK (tenant_id = #{@tenant})
    """)
  end

  defp sale_items_table do
    execute("ALTER TABLE sale_items ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE sale_items FORCE ROW LEVEL SECURITY")
    execute("DROP POLICY IF EXISTS sale_items_tenant_isolation ON sale_items")

    execute("""
    CREATE POLICY sale_items_tenant_isolation ON sale_items
      USING (sale_id IN (SELECT id FROM sales WHERE tenant_id = #{@tenant}))
      WITH CHECK (sale_id IN (SELECT id FROM sales WHERE tenant_id = #{@tenant}))
    """)
  end

  defp disable(table) do
    execute("DROP POLICY IF EXISTS #{table}_tenant_isolation ON #{table}")
    execute("ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY")
  end
end
