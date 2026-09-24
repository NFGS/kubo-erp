defmodule KuboErp.Repo.Migrations.CreateTenantCounters do
  use Ecto.Migration

  @moduledoc """
  Contador atomico de numeracion por negocio.

  Reemplaza el esquema de "maximo + reintento": `INSERT ... ON CONFLICT DO
  NOTHING` no permite distinguir con certeza si la fila se inserto (Ecto
  devuelve el id generado aunque la insercion se haya omitido), y bajo
  concurrencia eso producia lineas de venta apuntando a una venta inexistente.

  Con el contador, el numero se obtiene con un UPSERT atomico
  (`ON CONFLICT DO UPDATE ... RETURNING`), sin conflictos ni reintentos. La fila
  se bloquea hasta el final de la transaccion, de modo que la numeracion por
  negocio es estrictamente secuencial.

  La tabla no lleva RLS: es numeracion operativa, sin datos de negocio, y la
  escribe unicamente la transaccion de venta.
  """

  def up do
    execute("""
    CREATE TABLE tenant_counters (
      tenant_id uuid PRIMARY KEY,
      sale_seq  bigint NOT NULL DEFAULT 0
    )
    """)

    # Arranque desde el maximo ya emitido por cada negocio.
    execute("""
    INSERT INTO tenant_counters (tenant_id, sale_seq)
    SELECT tenant_id,
           COALESCE(MAX(NULLIF(regexp_replace(number, '\\D', '', 'g'), '')::bigint), 0)
    FROM sales
    GROUP BY tenant_id
    """)
  end

  def down do
    execute("DROP TABLE tenant_counters")
  end
end
