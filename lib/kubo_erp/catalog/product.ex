defmodule KuboErp.Catalog.Product do
  @moduledoc """
  Producto del catalogo. `price` es el precio final al publico (IVA incluido),
  como se maneja en el comercio colombiano; el impuesto se desagrega al facturar.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "products" do
    field(:tenant_id, :binary_id)
    field(:sku, :string)
    field(:name, :string)
    field(:description, :string)
    field(:unit, :string, default: "UN")
    field(:price, :decimal)
    field(:cost, :decimal)
    field(:tax_rate, :decimal, default: Decimal.new("19.00"))
    field(:stock, :integer, default: 0)
    field(:min_stock, :integer, default: 0)
    # Un servicio no lleva inventario (P-17): su venta no mueve kardex.
    field(:tracks_stock, :boolean, default: true)
    field(:active, :boolean, default: true)
    field(:deleted_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  def changeset(product, attrs) do
    product
    |> cast(attrs, [
      :sku,
      :name,
      :description,
      :unit,
      :price,
      :cost,
      :tax_rate,
      :min_stock,
      :tracks_stock,
      :active
    ])
    |> validate_required([:sku, :name, :price])
    |> validate_length(:sku, max: 60)
    |> validate_length(:name, max: 160)
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> validate_number(:cost, greater_than_or_equal_to: 0)
    |> validate_number(:tax_rate, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:min_stock, greater_than_or_equal_to: 0)
    |> unique_constraint([:tenant_id, :sku],
      name: :products_tenant_sku_unique,
      message: "ya existe un producto con ese SKU"
    )
  end

  def low_stock?(product), do: product.stock <= product.min_stock
end
