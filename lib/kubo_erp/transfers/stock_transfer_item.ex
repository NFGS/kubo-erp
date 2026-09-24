defmodule KuboErp.Transfers.StockTransferItem do
  @moduledoc "Linea de una transferencia entre bodegas (P-22)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stock_transfer_items" do
    field(:tenant_id, :binary_id)
    field(:transfer_id, :binary_id)
    field(:product_id, :binary_id)
    field(:quantity, :integer)

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:tenant_id, :transfer_id, :product_id, :quantity])
    |> validate_required([:tenant_id, :transfer_id, :product_id, :quantity])
    |> validate_number(:quantity, greater_than: 0)
  end
end
