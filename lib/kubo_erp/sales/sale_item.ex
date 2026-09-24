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
    belongs_to(:sale, KuboErp.Sales.Sale)
    # Denormalizado desde la venta: la politica de RLS lo compara por indice
    # (ver migracion 20260923000005).
    field(:tenant_id, :binary_id)
    field(:product_id, :binary_id)
    field(:product_name, :string)
    field(:quantity, :integer)
    field(:unit_price, :decimal)
    field(:tax_rate, :decimal)
    field(:tax_amount, :decimal)
    field(:total, :decimal)

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :sale_id,
      :tenant_id,
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
    # Una linea jamas debe apuntar a una venta inexistente: si ocurriera, el
    # error llega como changeset y no como excepcion.
    |> foreign_key_constraint(:sale_id)
  end
end
