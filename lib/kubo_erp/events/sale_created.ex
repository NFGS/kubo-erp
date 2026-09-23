defmodule KuboErp.Events.SaleCreated do
  @moduledoc """
  Construye el evento `sale.created` (version 1).

  El sobre del evento es estable (`event_id`, `event_type`, `version`,
  `occurred_at`, `tenant_id`, `data`) para que los consumidores puedan
  deduplicar por `event_id` y evolucionar por version.
  """

  @event_type "sale.created"
  @version 1

  def event_type, do: @event_type
  def version, do: @version

  def build(sale, items) do
    %{
      "event_id" => Ecto.UUID.generate(),
      "event_type" => @event_type,
      "version" => @version,
      "occurred_at" => iso8601(DateTime.utc_now()),
      "tenant_id" => sale.tenant_id,
      "data" => %{
        "sale_id" => sale.id,
        "number" => sale.number,
        "status" => sale.status,
        "customer_id" => sale.customer_id,
        "customer_name" => sale.customer_name,
        "payment_method" => sale.payment_method,
        "subtotal" => money(sale.subtotal),
        "tax" => money(sale.tax),
        "total" => money(sale.total),
        "sold_by" => sale.sold_by,
        "sold_at" => iso8601(sale.inserted_at),
        "items" => Enum.map(items, &item_payload/1)
      }
    }
  end

  defp item_payload(item) do
    %{
      "product_id" => item.product_id,
      "product_name" => item.product_name,
      "quantity" => item.quantity,
      "unit_price" => money(item.unit_price),
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
