defmodule KuboErp.Repo.Migrations.NotificationsSystemPolicy do
  use Ecto.Migration

  @moduledoc """
  Permite al entregador cruzar negocios (P-19, ADR-0017).

  El entregador de notificaciones es un proceso **de sistema**: barre pendientes
  de todos los negocios, como el publicador de la bandeja de salida. La politica
  sigue aislando por negocio en el camino de la peticion; la marca `app.system`
  (que solo fija el propio proceso) abre la tabla para el barrido.
  """

  def up do
    execute("DROP POLICY IF EXISTS notifications_tenant_isolation ON notifications")

    execute("""
    CREATE POLICY notifications_tenant_isolation ON notifications
      USING (
        tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid
        OR current_setting('app.system', true) = 'on'
      )
      WITH CHECK (
        tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid
        OR current_setting('app.system', true) = 'on'
      )
    """)
  end

  def down do
    execute("DROP POLICY IF EXISTS notifications_tenant_isolation ON notifications")

    execute("""
    CREATE POLICY notifications_tenant_isolation ON notifications
      USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
      WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
    """)
  end
end
