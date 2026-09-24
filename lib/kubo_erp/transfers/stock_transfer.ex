defmodule KuboErp.Transfers.StockTransfer do
  @moduledoc "Transferencia entre bodegas (P-22, ADR-0016)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stock_transfers" do
    field(:tenant_id, :binary_id)
    field(:from_warehouse_id, :binary_id)
    field(:to_warehouse_id, :binary_id)
    field(:status, :string, default: "COMPLETED")
    field(:notes, :string)
    field(:created_by, :binary_id)
    field(:completed_at, :utc_datetime)

    has_many(:items, KuboErp.Transfers.StockTransferItem, foreign_key: :transfer_id)

    timestamps(type: :utc_datetime)
  end

  def changeset(transfer, attrs) do
    transfer
    |> cast(attrs, [
      :tenant_id,
      :from_warehouse_id,
      :to_warehouse_id,
      :status,
      :notes,
      :created_by,
      :completed_at
    ])
    |> validate_required([:tenant_id, :from_warehouse_id, :to_warehouse_id])
    |> validate_inclusion(:status, ~w[COMPLETED VOIDED])
  end
end
