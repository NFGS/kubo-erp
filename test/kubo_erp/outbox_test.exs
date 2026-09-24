defmodule KuboErp.OutboxTest do
  @moduledoc """
  Pruebas puras de la bandeja de salida: la espera exponencial y la forma del
  sobre del evento. No requieren base de datos ni bus.
  """

  use ExUnit.Case, async: true

  alias KuboErp.Events.{Outbox, OutboxEvent, SaleCreated}
  alias KuboErp.Sales.Sale

  test "la espera exponencial crece y se acota" do
    assert Outbox.backoff_seconds(1) == 2
    assert Outbox.backoff_seconds(2) == 4
    assert Outbox.backoff_seconds(3) == 8
    assert Outbox.backoff_seconds(8) == 256
    assert Outbox.backoff_seconds(9) == 300
    assert Outbox.backoff_seconds(50) == 300
  end

  test "el sobre del evento se puede guardar en la bandeja" do
    sale = %Sale{
      id: Ecto.UUID.generate(),
      tenant_id: Ecto.UUID.generate(),
      number: "V-000001",
      status: "COMPLETED",
      payment_method: "CASH",
      subtotal: Decimal.new("10000.00"),
      tax: Decimal.new("1900.00"),
      total: Decimal.new("11900.00"),
      inserted_at: DateTime.utc_now()
    }

    event = SaleCreated.build(sale, [])

    changeset =
      OutboxEvent.changeset(%OutboxEvent{}, %{
        event_id: event["event_id"],
        event_type: event["event_type"],
        tenant_id: event["tenant_id"],
        payload: event,
        status: "PENDING",
        attempts: 0,
        available_at: DateTime.utc_now()
      })

    assert changeset.valid?
    assert event["version"] == 1
    assert event["data"]["total"] == "11900.00"
  end

  test "un estado desconocido no es valido en la bandeja" do
    changeset =
      OutboxEvent.changeset(%OutboxEvent{}, %{
        event_id: Ecto.UUID.generate(),
        event_type: "sale.created",
        tenant_id: Ecto.UUID.generate(),
        payload: %{"event_id" => "x"},
        status: "VOLANDO",
        available_at: DateTime.utc_now()
      })

    refute changeset.valid?
  end
end
