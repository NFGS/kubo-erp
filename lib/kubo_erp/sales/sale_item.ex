defmodule KuboErp.Sales.SaleItem do
  @moduledoc """
  Linea de venta. Guarda una copia del nombre, del precio y de la tarifa de
  impuesto: el historico comercial no cambia aunque el producto se modifique.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sale_items" do
    belongs_to :sale, KuboErp.Sales.Sale
    field :product_id, :binary_id
    field :product_name, :string
    field :quantity, :integer
    field :unit_price, :decimal
    field :tax_rate, :decimal
    field :tax_amount, :decimal
    field :total, :decimal

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :sale_id,
      :product_id,
      :product_name,
      :quantity,
      :unit_price,
      :tax_rate,
      :tax_amount,
      :total
    ])
    |> validate_required([:product_id, :product_name, :quantity, :unit_price, :total])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:unit_price, greater_than_or_equal_to: 0)
  end
end
