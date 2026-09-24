defmodule KuboErp.Catalog.StockLevel do
  @moduledoc """
  Existencia de un producto en una bodega (P-22, ADR-0016).

  Es la **fuente de verdad** del inventario; `products.stock` es el total
  denormalizado que se mantiene en la misma transaccion para las lecturas
  rapidas (POS, reportes, tablero).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stock_levels" do
    field(:tenant_id, :binary_id)
    field(:warehouse_id, :binary_id)
    field(:product_id, :binary_id)
    field(:stock, :integer, default: 0)

    timestamps(type: :utc_datetime)
  end

  def changeset(level, attrs) do
    level
    |> cast(attrs, [:tenant_id, :warehouse_id, :product_id, :stock])
    |> validate_required([:tenant_id, :warehouse_id, :product_id])
    |> validate_number(:stock, greater_than_or_equal_to: 0)
    |> unique_constraint([:tenant_id, :warehouse_id, :product_id],
      name: :stock_levels_warehouse_product_unique
    )
  end
end
