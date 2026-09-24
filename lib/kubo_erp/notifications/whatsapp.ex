defmodule KuboErp.Notifications.Whatsapp do
  @moduledoc """
  Adaptador de WhatsApp Cloud API (P-19, ADR-0017).

  Se selecciona con `KUBO_NOTIFICATIONS_ADAPTER=whatsapp` y toma las credenciales
  de `KUBO_WHATSAPP_TOKEN` y `KUBO_WHATSAPP_PHONE_ID`; el destinatario es el del
  aviso o `KUBO_NOTIFICATIONS_WHATSAPP` (el numero del dueno).

  Sin credenciales falla con un error claro y el entregador reintenta: el aviso
  ya quedo registrado en el buzon, asi que nada se pierde.
  """

  @behaviour KuboErp.Notifications

  alias KuboErp.Notifications.Notification

  @impl true
  def deliver(%Notification{} = notification) do
    with {:ok, config} <- configuracion(),
         destinatario when is_binary(destinatario) <- notification.recipient || config.recipient do
      url = "https://graph.facebook.com/#{config.version}/#{config.phone_id}/messages"

      case :hackney.request(
             :post,
             url,
             [{"Authorization", "Bearer #{config.token}"}, {"Content-Type", "application/json"}],
             build_payload(notification, destinatario),
             []
           ) do
        {:ok, 200, _headers, _body} -> :ok
        {:ok, status, _headers, _body} -> {:error, {:http, status}}
        {:error, razon} -> {:error, razon}
      end
    else
      nil -> {:error, :no_recipient}
      {:error, razon} -> {:error, razon}
    end
  end

  @doc "Cuerpo que espera la Cloud API (expuesto para las pruebas)."
  def build_payload(%Notification{} = notification, destinatario) do
    Jason.encode!(%{
      messaging_product: "whatsapp",
      to: destinatario,
      type: "text",
      text: %{body: "#{notification.subject}\n#{notification.body}"}
    })
  end

  defp configuracion do
    token = System.get_env("KUBO_WHATSAPP_TOKEN")
    phone_id = System.get_env("KUBO_WHATSAPP_PHONE_ID")

    if token && phone_id do
      {:ok,
       %{
         token: token,
         phone_id: phone_id,
         version: System.get_env("KUBO_WHATSAPP_API_VERSION", "v21.0"),
         recipient: System.get_env("KUBO_NOTIFICATIONS_WHATSAPP")
       }}
    else
      {:error, :whatsapp_not_configured}
    end
  end
end
