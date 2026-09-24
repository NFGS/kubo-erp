defmodule KuboErp.Warehouses do
  @moduledoc """
  Bodegas del negocio (P-22, ADR-0016).

  Todo negocio tiene exactamente una bodega por defecto: la migracion se la creo
  a los existentes y aqui se crea de forma perezosa para los negocios nuevos
  (el ERP no participa del registro, que vive en IAM).
  """

  import Ecto.Query

  alias KuboErp.Repo
  alias KuboErp.Warehouses.Warehouse

  @default_name "Bodega principal"

  def list(tenant_id) do
    Warehouse
    |> where([w], w.tenant_id == ^tenant_id and is_nil(w.deleted_at))
    |> order_by([w], desc: w.is_default, asc: w.name)
    |> Repo.all()
  end

  def get(tenant_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        Warehouse
        |> where([w], w.tenant_id == ^tenant_id and w.id == ^uuid and is_nil(w.deleted_at))
        |> Repo.one()

      :error ->
        nil
    end
  end

  @doc "Bodega por defecto del negocio; se crea si el negocio es nuevo."
  def default(tenant_id) do
    case Repo.one(
           from(w in Warehouse,
             where: w.tenant_id == ^tenant_id and w.is_default and is_nil(w.deleted_at)
           )
         ) do
      nil -> crear_default(tenant_id)
      warehouse -> warehouse
    end
  end

  def create(tenant_id, attrs) do
    %Warehouse{tenant_id: tenant_id}
    |> Warehouse.changeset(attrs)
    |> Repo.insert()
  end

  def update(%Warehouse{} = warehouse, attrs) do
    warehouse |> Warehouse.changeset(attrs) |> Repo.update()
  end

  @doc """
  Borra (logicamente) una bodega.

  No se borra la bodega por defecto —el negocio se quedaria sin donde vender— ni
  una con existencia: primero se traslada o se ajusta.
  """
  def soft_delete(%Warehouse{is_default: true}), do: {:error, :default_warehouse}

  def soft_delete(%Warehouse{} = warehouse) do
    if con_existencia?(warehouse) do
      {:error, :warehouse_not_empty}
    else
      warehouse
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update()
    end
  end

  defp con_existencia?(warehouse) do
    Repo.exists?(
      from(l in KuboErp.Catalog.StockLevel,
        where: l.warehouse_id == ^warehouse.id and l.stock != 0
      )
    )
  end

  defp crear_default(tenant_id) do
    {:ok, warehouse} =
      %Warehouse{}
      |> Ecto.Changeset.change(%{
        tenant_id: tenant_id,
        name: @default_name,
        is_default: true,
        active: true
      })
      |> Repo.insert()

    warehouse
  end
end
