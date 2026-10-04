defmodule KuboErp.Purchasing.Purchase do
  @moduledoc """
  Compra recibida de un proveedor.

  Guarda una copia del nombre del proveedor para que el historico no cambie si
  el proveedor se renombra o se archiva.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "purchases" do
    field(:tenant_id, :binary_id)
    field(:number, :string)
    field(:supplier_name, :string)
    field(:status, :string, default: "RECEIVED")
    field(:subtotal, :decimal)
    field(:tax, :decimal)
    field(:total, :decimal)
    field(:notes, :string)
    field(:received_by, :binary_id)
    field(:received_at, :utc_datetime)
    field(:voided_at, :utc_datetime)

    # Bodega a la que entro la mercancia (P-22): la anulacion revierte alli.
    field(:warehouse_id, :binary_id)

    belongs_to(:supplier, KuboErp.Purchasing.Supplier)
    has_many(:items, KuboErp.Purchasing.PurchaseItem)

    timestamps(type: :utc_datetime)
  end

  def changeset(purchase, attrs) do
    purchase
    |> cast(attrs, [
      :tenant_id,
      :number,
      :supplier_id,
      :supplier_name,
      :status,
      :subtotal,
      :tax,
      :total,
      :notes,
      :received_by,
      :received_at,
      :voided_at,
      :warehouse_id
    ])
    |> validate_required([:tenant_id, :number, :supplier_id, :supplier_name, :received_at])
    |> validate_inclusion(:status, ["RECEIVED", "VOIDED"])
    |> unique_constraint(:number, name: :purchases_tenant_number_index)
    |> foreign_key_constraint(:supplier_id)
  end
end
