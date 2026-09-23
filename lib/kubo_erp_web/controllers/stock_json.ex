defmodule KuboErpWeb.StockJSON do
  @moduledoc """
  Representacion JSON del kardex y de los ajustes de inventario.

  Phoenix deriva el modulo de vista del nombre del controlador: `StockController`
  busca `KuboErpWeb.StockJSON`. Por eso estas funciones viven aqui y no en
  `ProductJSON`.
  """

  def movements(%{movements: movements}) do
    %{data: Enum.map(movements, &movement_data/1), total: length(movements)}
  end

  def stock(%{product: product, movement: movement}) do
    %{data: %{product: product_data(product), movement: movement_data(movement)}}
  end

  defp product_data(product) do
    %{
      id: product.id,
      sku: product.sku,
      name: product.name,
      unit: product.unit,
      price: money(product.price),
      stock: product.stock,
      min_stock: product.min_stock,
      low_stock: product.stock <= product.min_stock,
      active: product.active
    }
  end

  defp movement_data(movement) do
    %{
      id: movement.id,
      product_id: movement.product_id,
      kind: movement.kind,
      quantity: movement.quantity,
      stock_after: movement.stock_after,
      reason: movement.reason,
      reference_type: movement.reference_type,
      reference_id: movement.reference_id,
      created_at: iso(movement.inserted_at)
    }
  end

  defp money(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp money(value), do: value

  defp iso(nil), do: nil
  defp iso(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
