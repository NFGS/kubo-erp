defmodule KuboErp.Notifications.SmtpTest do
  @moduledoc """
  Adaptador de correo (P-19). No envia nada: valida el correo que se enviaria.
  """

  use ExUnit.Case, async: true

  alias KuboErp.Notifications.Notification
  alias KuboErp.Notifications.Smtp

  test "el correo lleva destinatario, asunto y cuerpo del aviso" do
    aviso = %Notification{subject: "Stock bajo de Arroz", body: "Quedan 2 unidades de Arroz."}

    correo = Smtp.build_email(aviso, "dueno@kubo.local", "no-responder@kubo.local")

    assert correo.to == [{"", "dueno@kubo.local"}]
    assert correo.from == {"", "no-responder@kubo.local"}
    assert correo.subject == "Stock bajo de Arroz"
    assert correo.text_body == "Quedan 2 unidades de Arroz."
  end
end
