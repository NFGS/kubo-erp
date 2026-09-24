defmodule KuboErp.Repo.Migrations.BackfillTenantCounters do
  use Ecto.Migration

  @moduledoc """
  Corrige el relleno inicial de `tenant_counters`.

  La migracion anterior agrupo `sales` sin desactivar RLS, de modo que la
  consulta no vio ninguna fila y el contador arranco en cero: la primera venta
  de cada negocio volvia a emitir un numero ya usado. Aqui el relleno corre como
  dueno sin FORCE (ve todas las filas) y es idempotente: para un negocio con
  contador, conserva el mayor valor.
  """

  def up do
    execute("ALTER TABLE sales NO FORCE ROW LEVEL SECURITY")

    execute("""
    INSERT INTO tenant_counters (tenant_id, sale_seq)
    SELECT tenant_id,
           COALESCE(MAX(NULLIF(regexp_replace(number, '\\D', '', 'g'), '')::bigint), 0)
    FROM sales
    GROUP BY tenant_id
    ON CONFLICT (tenant_id)
    DO UPDATE SET sale_seq = GREATEST(tenant_counters.sale_seq, EXCLUDED.sale_seq)
    """)

    execute("ALTER TABLE sales FORCE ROW LEVEL SECURITY")
  end

  def down do
    :ok
  end
end
