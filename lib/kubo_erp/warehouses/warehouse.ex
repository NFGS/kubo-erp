defmodule KuboErp.Warehouses.Warehouse do
  @moduledoc "Bodega o local donde hay existencia (P-22, ADR-0016)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "warehouses" do
    field(:tenant_id, :binary_id)
    field(:name, :string)
    field(:address, :string)
    field(:is_default, :boolean, default: false)
    field(:active, :boolean, default: true)
    field(:deleted_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  def changeset(warehouse, attrs) do
    warehouse
    |> cast(attrs, [:name, :address, :active])
    |> validate_required([:name])
    |> validate_length(:name, max: 120)
    |> validate_length(:address, max: 200)
  end
end
