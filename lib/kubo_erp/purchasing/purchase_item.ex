defmodule KuboErp.Purchasing.PurchaseItem do
  @moduledoc "Linea de compra: producto, cantidad y costo unitario con IVA incluido."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "purchase_items" do
    belongs_to(:purchase, KuboErp.Purchasing.Purchase)

    # Denormalizado desde la compra para que la politica de RLS sea por indice.
    field(:tenant_id, :binary_id)
    field(:product_id, :binary_id)
    field(:product_name, :string)
    field(:quantity, :integer)
    field(:unit_cost, :decimal)
    field(:tax_rate, :decimal)
    field(:tax_amount, :decimal)
    field(:total, :decimal)

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :purchase_id,
      :tenant_id,
      :product_id,
      :product_name,
      :quantity,
      :unit_cost,
      :tax_rate,
      :tax_amount,
      :total
    ])
    |> validate_required([:tenant_id, :product_id, :product_name, :quantity, :unit_cost, :total])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:unit_cost, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:purchase_id)
  end
end
