defmodule KuboErp.Catalog.StockMovement do
  @moduledoc """
  Movimiento de inventario (kardex). Es la fuente de verdad del stock: el campo
  `products.stock` es una proyeccion para lecturas rapidas.

  `reference_type` + `reference_id` + `product_id` son unicos, de modo que
  reintentar una venta no descuenta dos veces el inventario.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @kinds ~w[IN OUT ADJUST]

  schema "stock_movements" do
    field :tenant_id, :binary_id
    field :product_id, :binary_id
    field :kind, :string
    field :quantity, :integer
    field :stock_after, :integer
    field :reason, :string
    field :reference_type, :string
    field :reference_id, :binary_id
    # Bodega del movimiento (P-22): el kardex es por bodega.
    field :warehouse_id, :binary_id
    field :created_by, :binary_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def kinds, do: @kinds

  def changeset(movement, attrs) do
    movement
    |> cast(attrs, [
      :tenant_id,
      :product_id,
      :kind,
      :quantity,
      :stock_after,
      :reason,
      :reference_type,
      :reference_id,
      :warehouse_id,
      :created_by
    ])
    |> validate_required([:tenant_id, :product_id, :kind, :quantity, :stock_after])
    |> validate_inclusion(:kind, @kinds)
    |> validate_number(:quantity, greater_than: 0)
  end
end
