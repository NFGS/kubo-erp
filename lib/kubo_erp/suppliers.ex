defmodule KuboErp.Suppliers do
  @moduledoc """
  Proveedores del negocio (P-15).

  CRUD con borrado logico y paginacion real, igual que el catalogo. Un proveedor
  con compras no se borra fisicamente: el historico de compras lo referencia.
  """

  import Ecto.Query

  alias KuboErp.{Pagination, Repo}
  alias KuboErp.Purchasing.Supplier

  def list(tenant_id, filters \\ %{}) do
    {limit, offset} = Pagination.normalize(filters)

    tenant_id
    |> base(filters)
    |> order_by([s], asc: s.name)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  def count(tenant_id, filters \\ %{}) do
    tenant_id |> base(filters) |> Repo.aggregate(:count)
  end

  defp base(tenant_id, filters) do
    Supplier
    |> where([s], s.tenant_id == ^tenant_id and is_nil(s.deleted_at))
    |> filter_query(filters["q"])
    |> filter_active(filters["active"])
  end

  def get(_tenant_id, nil), do: nil

  def get(tenant_id, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id) do
      Supplier
      |> where([s], s.tenant_id == ^tenant_id and s.id == ^uuid and is_nil(s.deleted_at))
      |> Repo.one()
    else
      :error -> nil
    end
  end

  def create(tenant_id, attrs) do
    %Supplier{tenant_id: tenant_id}
    |> Supplier.changeset(attrs)
    |> Repo.insert()
  end

  def update(supplier, attrs) do
    supplier
    |> Supplier.changeset(attrs)
    |> Repo.update()
  end

  def soft_delete(supplier) do
    supplier
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  defp filter_query(query, term) when is_binary(term) and term != "" do
    sanitized = String.replace(term, ["%", "_", "\\"], "")
    like = "%" <> sanitized <> "%"
    from(s in query, where: ilike(s.name, ^like) or ilike(s.tax_id, ^like))
  end

  defp filter_query(query, _term), do: query

  defp filter_active(query, "true"), do: from(s in query, where: s.active)
  defp filter_active(query, "false"), do: from(s in query, where: not s.active)
  defp filter_active(query, _value), do: query
end
