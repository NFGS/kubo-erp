defmodule KuboErpWeb.ProductJSON do
  @moduledoc "Representacion JSON de productos del catalogo."

  alias KuboErp.Catalog.Product

  def index(%{products: products, total: total, limit: limit, offset: offset}) do
    %{
      data: Enum.map(products, &data/1),
      total: total,
      limit: limit,
      offset: offset
    }
  end

  def show(%{product: product}), do: %{data: data(product)}
  def stats(%{stats: stats}), do: %{data: stats}

  defp data(product) do
    %{
      id: product.id,
      sku: product.sku,
      name: product.name,
      description: product.description,
      unit: product.unit,
      price: money(product.price),
      cost: money(product.cost),
      tax_rate: money(product.tax_rate),
      stock: product.stock,
      min_stock: product.min_stock,
      # La regla de "stock bajo" vive en el dominio, no en la capa de presentacion.
      low_stock: Product.low_stock?(product),
      active: product.active,
      created_at: iso(product.inserted_at),
      updated_at: iso(product.updated_at)
    }
  end

  defp money(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp money(value), do: value

  defp iso(nil), do: nil
  defp iso(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
