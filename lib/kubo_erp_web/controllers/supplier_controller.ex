defmodule KuboErpWeb.SupplierController do
  @moduledoc "CRUD de proveedores (P-15)."

  use KuboErpWeb, :controller

  alias KuboErp.{Pagination, Suppliers}

  def index(conn, params) do
    {limit, offset} = Pagination.normalize(params)
    suppliers = Suppliers.list(conn.assigns.tenant_id, params)
    total = Suppliers.count(conn.assigns.tenant_id, params)

    render(conn, :index, suppliers: suppliers, total: total, limit: limit, offset: offset)
  end

  def show(conn, %{"id" => id}) do
    case Suppliers.get(conn.assigns.tenant_id, id) do
      nil -> not_found(conn)
      supplier -> render(conn, :show, supplier: supplier)
    end
  end

  def create(conn, params) do
    attrs = params["supplier"] || params

    case Suppliers.create(conn.assigns.tenant_id, attrs) do
      {:ok, supplier} -> conn |> put_status(:created) |> render(:show, supplier: supplier)
      {:error, changeset} -> validation_error(conn, changeset)
    end
  end

  def update(conn, %{"id" => id} = params) do
    attrs = params["supplier"] || params

    case Suppliers.get(conn.assigns.tenant_id, id) do
      nil ->
        not_found(conn)

      supplier ->
        case Suppliers.update(supplier, attrs) do
          {:ok, updated} -> render(conn, :show, supplier: updated)
          {:error, changeset} -> validation_error(conn, changeset)
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case Suppliers.get(conn.assigns.tenant_id, id) do
      nil ->
        not_found(conn)

      supplier ->
        {:ok, _} = Suppliers.soft_delete(supplier)
        send_resp(conn, :no_content, "")
    end
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{code: "SUPPLIER_NOT_FOUND", message: "El proveedor no existe"})
  end

  defp validation_error(conn, changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "VALIDATION_ERROR",
      message: errors_to_string(changeset),
      fields: Map.keys(changeset.errors)
    })
  end

  defp errors_to_string(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {message, _opts}} ->
      "#{field} #{message}"
    end)
  end
end
