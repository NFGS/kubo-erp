defmodule KuboErpWeb.PurchaseJSON do
  @moduledoc "Representacion JSON de compras y su detalle."

  def index(%{purchases: purchases, total: total, limit: limit, offset: offset}) do
    %{
      data: Enum.map(purchases, &data/1),
      total: total,
      limit: limit,
      offset: offset
    }
  end

  def show(%{purchase: purchase}), do: %{data: data(purchase)}
  def stats(%{stats: stats}), do: %{data: stats}

  defp data(purchase) do
    %{
      id: purchase.id,
      number: purchase.number,
      status: purchase.status,
      supplier_id: purchase.supplier_id,
      supplier_name: purchase.supplier_name,
      subtotal: money(purchase.subtotal),
      tax: money(purchase.tax),
      total: money(purchase.total),
      notes: purchase.notes,
      received_by: purchase.received_by,
      received_at: iso(purchase.received_at),
      voided_at: iso(purchase.voided_at),
      warehouse_id: purchase.warehouse_id,
      items: Enum.map(purchase.items || [], &item_data/1)
    }
  end

  defp item_data(item) do
    %{
      id: item.id,
      product_id: item.product_id,
      product_name: item.product_name,
      quantity: item.quantity,
      unit_cost: money(item.unit_cost),
      tax_rate: money(item.tax_rate),
      tax_amount: money(item.tax_amount),
      total: money(item.total)
    }
  end

  defp money(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp money(value), do: value

  defp iso(nil), do: nil
  defp iso(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
