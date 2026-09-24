defmodule KuboErp.Events.PurchaseReceived do
  @moduledoc """
  Construye el evento `purchase.received` (version 1).

  Mismo sobre estable que `sale.created`: los consumidores deduplican por
  `event_id` y evolucionan por version. Hoy analitica lo ignora (no tiene
  proyeccion asociada); el evento queda listo para notificaciones y para el
  costo promedio en el tablero.
  """

  @event_type "purchase.received"
  @version 1

  def event_type, do: @event_type
  def version, do: @version

  def build(purchase, items) do
    %{
      "event_id" => Ecto.UUID.generate(),
      "event_type" => @event_type,
      "version" => @version,
      "occurred_at" => iso8601(DateTime.utc_now()),
      "tenant_id" => purchase.tenant_id,
      "data" => %{
        "purchase_id" => purchase.id,
        "number" => purchase.number,
        "status" => purchase.status,
        "supplier_id" => purchase.supplier_id,
        "supplier_name" => purchase.supplier_name,
        "subtotal" => money(purchase.subtotal),
        "tax" => money(purchase.tax),
        "total" => money(purchase.total),
        "received_by" => purchase.received_by,
        "received_at" => iso8601(purchase.received_at),
        "items" => Enum.map(items, &item_payload/1)
      }
    }
  end

  defp item_payload(item) do
    %{
      "product_id" => item.product_id,
      "product_name" => item.product_name,
      "quantity" => item.quantity,
      "unit_cost" => money(item.unit_cost),
      "tax_rate" => money(item.tax_rate),
      "tax_amount" => money(item.tax_amount),
      "total" => money(item.total)
    }
  end

  defp money(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp money(value), do: to_string(value)

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
