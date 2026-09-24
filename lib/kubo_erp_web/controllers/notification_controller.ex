defmodule KuboErpWeb.NotificationController do
  @moduledoc "Buzon de notificaciones del negocio (P-19)."

  use KuboErpWeb, :controller

  alias KuboErp.Notifications

  def index(conn, _params) do
    render(conn, :index, notifications: Notifications.list(conn.assigns.tenant_id))
  end
end
