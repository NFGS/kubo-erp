defmodule KuboErp.Notifications.Log do
  @moduledoc """
  Adaptador por defecto: el aviso queda en el buzon del negocio y en el log.

  No entrega nada fuera del sistema; sirve para desarrollo, para la demostracion
  y como registro de lo que un proveedor real habria enviado.
  """

  @behaviour KuboErp.Notifications

  require Logger

  alias KuboErp.Notifications.Notification

  @impl true
  def deliver(%Notification{} = notification) do
    Logger.info("Notificacion para el negocio #{notification.tenant_id}: #{notification.subject}")

    :ok
  end
end
