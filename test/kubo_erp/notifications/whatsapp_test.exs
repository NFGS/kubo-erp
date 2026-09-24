defmodule KuboErp.Notifications.WhatsappTest do
  @moduledoc """
  Adaptador de WhatsApp (P-19). No envia nada: valida el cuerpo que enviaria.
  """

  use ExUnit.Case, async: true

  alias KuboErp.Notifications.Notification
  alias KuboErp.Notifications.Whatsapp

  test "el mensaje lleva destinatario y el texto del aviso" do
    aviso = %Notification{subject: "Stock bajo de Arroz", body: "Quedan 2 unidades."}

    payload = Whatsapp.build_payload(aviso, "573001234567") |> Jason.decode!()

    assert payload["messaging_product"] == "whatsapp"
    assert payload["to"] == "573001234567"
    assert payload["type"] == "text"
    assert payload["text"]["body"] == "Stock bajo de Arroz\nQuedan 2 unidades."
  end
end
