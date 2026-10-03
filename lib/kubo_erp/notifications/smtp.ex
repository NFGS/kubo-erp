defmodule KuboErp.Notifications.Smtp do
  @moduledoc """
  Adaptador de correo real (P-19, ADR-0017).

  Reutiliza la configuracion de correo del sistema (`KUBO_SMTP_*`, la misma
  familia que usa IAM) y envia con Swoosh. El destinatario es el del aviso o,
  si no lo trae, el buzon del negocio (`KUBO_NOTIFICATIONS_EMAIL`).

  Se selecciona con `KUBO_NOTIFICATIONS_ADAPTER=smtp`; sin configuracion valida
  el adaptador falla con un error claro y el entregador reintenta (nunca tumba
  la operacion de negocio, que ya quedo registrada).
  """

  @behaviour KuboErp.Notifications

  alias KuboErp.Notifications.Notification

  @impl true
  def deliver(%Notification{} = notification) do
    with {:ok, config} <- configuracion(),
         destinatario when is_binary(destinatario) <- notification.recipient || config.recipient do
      notification
      |> build_email(destinatario, config.from)
      |> KuboErp.Mailer.deliver()
      |> case do
        {:ok, _resultado} -> :ok
        {:error, razon} -> {:error, razon}
      end
    else
      nil -> {:error, :no_recipient}
      {:error, razon} -> {:error, razon}
    end
  end

  @doc "Correo del aviso (expuesto para las pruebas)."
  def build_email(%Notification{} = notification, destinatario, from) do
    Swoosh.Email.new()
    |> Swoosh.Email.to(destinatario)
    |> Swoosh.Email.from(from)
    |> Swoosh.Email.subject(notification.subject)
    |> Swoosh.Email.text_body(notification.body)
  end

  defp configuracion do
    config = Application.get_env(:kubo_erp, :smtp, [])

    if config[:host] do
      {:ok,
       %{
         from: config[:from] || "no-responder@kubo.local",
         recipient: config[:recipient]
       }}
    else
      {:error, :smtp_not_configured}
    end
  end
end
