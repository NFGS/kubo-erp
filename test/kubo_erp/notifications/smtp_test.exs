defmodule KuboErp.Notifications.SmtpTest do
  @moduledoc """
  Adaptador de correo (P-19). La entrega se prueba con el adaptador de prueba de
  Swoosh: valida el correo que se enviaria, sin tocar un servidor real.
  """

  use ExUnit.Case, async: false

  import Swoosh.TestAssertions

  alias KuboErp.Notifications.Notification
  alias KuboErp.Notifications.Smtp

  setup do
    # La entrega se prueba contra el adaptador de prueba; al terminar se
    # restaura la configuracion de runtime (SMTP en el sistema real).
    mailer = Application.get_env(:kubo_erp, KuboErp.Mailer)
    smtp = Application.get_env(:kubo_erp, :smtp)

    Application.put_env(:kubo_erp, KuboErp.Mailer, adapter: Swoosh.Adapters.Test)

    Application.put_env(:kubo_erp, :smtp,
      host: "smtp.test",
      from: "no-responder@kubo.local",
      recipient: "buzon@kubo.local"
    )

    on_exit(fn ->
      if mailer do
        Application.put_env(:kubo_erp, KuboErp.Mailer, mailer)
      else
        Application.delete_env(:kubo_erp, KuboErp.Mailer)
      end

      if smtp do
        Application.put_env(:kubo_erp, :smtp, smtp)
      else
        Application.delete_env(:kubo_erp, :smtp)
      end
    end)

    :ok
  end

  test "el correo lleva destinatario, asunto y cuerpo del aviso" do
    aviso = %Notification{subject: "Stock bajo de Arroz", body: "Quedan 2 unidades de Arroz."}

    correo = Smtp.build_email(aviso, "dueno@kubo.local", "no-responder@kubo.local")

    assert correo.to == [{"", "dueno@kubo.local"}]
    assert correo.from == {"", "no-responder@kubo.local"}
    assert correo.subject == "Stock bajo de Arroz"
    assert correo.text_body == "Quedan 2 unidades de Arroz."
  end

  test "la entrega pasa por el mailer del proyecto" do
    aviso = %Notification{subject: "Stock bajo de Arroz", body: "Quedan 2 unidades de Arroz."}

    assert :ok = Smtp.deliver(aviso)

    assert_email_sent(
      subject: "Stock bajo de Arroz",
      to: "buzon@kubo.local",
      text_body: "Quedan 2 unidades de Arroz."
    )
  end

  test "sin servidor configurado la entrega falla con un error claro" do
    Application.delete_env(:kubo_erp, :smtp)

    aviso = %Notification{subject: "Stock bajo", body: "Sin servidor."}

    assert {:error, :smtp_not_configured} = Smtp.deliver(aviso)
  end
end
