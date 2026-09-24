defmodule KuboErpWeb.NotificationJSON do
  @moduledoc "Representacion JSON del buzon de notificaciones (P-19)."

  def index(%{notifications: notifications}), do: %{data: Enum.map(notifications, &data/1)}

  defp data(notification) do
    %{
      id: notification.id,
      kind: notification.kind,
      channel: notification.channel,
      subject: notification.subject,
      body: notification.body,
      status: notification.status,
      reference_type: notification.reference_type,
      reference_id: notification.reference_id,
      sent_at: iso(notification.sent_at),
      created_at: iso(notification.inserted_at)
    }
  end

  defp iso(nil), do: nil
  defp iso(%DateTime{} = valor), do: DateTime.to_iso8601(valor)
  defp iso(%NaiveDateTime{} = valor), do: NaiveDateTime.to_iso8601(valor)
end
