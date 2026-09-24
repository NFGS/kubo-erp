defmodule KuboErp.Notifications.Log do
  @moduledoc """
  Adaptador de notificaciones por defecto: deja el aviso en el buzon del negocio.

  No entrega nada fuera del sistema; sirve para desarrollo, para la
  demostracion y como registro de lo que un proveedor real habria enviado.
  """

  @behaviour KuboErp.Notifications

  require Logger

  alias KuboErp.Repo
  alias KuboErp.Notifications.Notification

  @impl true
  def deliver(attrs) do
    Logger.info("Notificacion para el negocio #{attrs.tenant_id}: #{attrs.subject}")

    %Notification{}
    |> Notification.changeset(
      Map.merge(attrs, %{
        channel: "LOG",
        status: "SENT",
        sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    )
    |> Repo.insert()
  end
end
