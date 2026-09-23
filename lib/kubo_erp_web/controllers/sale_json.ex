defmodule KuboErpWeb.SaleJSON do
  @moduledoc "Representacion JSON de ventas y su detalle."

  def index(%{sales: sales}) do
    %{data: Enum.map(sales, &data/1), total: length(sales)}
  end

  def show(%{sale: sale}), do: %{data: data(sale)}
  def stats(%{stats: stats}), do: %{data: stats}

  defp data(sale) do
    %{
      id: sale.id,
      number: sale.number,
      status: sale.status,
      customer_id: sale.customer_id,
      customer_name: sale.customer_name,
      payment_method: sale.payment_method,
      subtotal: money(sale.subtotal),
      tax: money(sale.tax),
      total: money(sale.total),
      notes: sale.notes,
      sold_by: sale.sold_by,
      voided_at: iso(sale.voided_at),
      created_at: iso(sale.inserted_at),
      items: Enum.map(sale.items || [], &item_data/1)
    }
  end

  defp item_data(item) do
    %{
      id: item.id,
      product_id: item.product_id,
      product_name: item.product_name,
      quantity: item.quantity,
      unit_price: money(item.unit_price),
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
