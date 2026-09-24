defmodule KuboErpWeb.WarehouseController do
  @moduledoc "Bodegas del negocio (P-22, ADR-0016)."

  use KuboErpWeb, :controller

  alias KuboErp.Warehouses

  def index(conn, _params) do
    render(conn, :index, warehouses: Warehouses.list(conn.assigns.tenant_id))
  end

  def show(conn, %{"id" => id}) do
    case Warehouses.get(conn.assigns.tenant_id, id) do
      nil -> error(conn, :not_found, "WAREHOUSE_NOT_FOUND", "La bodega no existe")
      warehouse -> render(conn, :show, warehouse: warehouse)
    end
  end

  def create(conn, params) do
    case Warehouses.create(conn.assigns.tenant_id, params) do
      {:ok, warehouse} ->
        conn |> put_status(:created) |> render(:show, warehouse: warehouse)

      {:error, changeset} ->
        validation_error(conn, changeset)
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Warehouses.get(conn.assigns.tenant_id, id) do
      nil ->
        error(conn, :not_found, "WAREHOUSE_NOT_FOUND", "La bodega no existe")

      warehouse ->
        case Warehouses.update(warehouse, params) do
          {:ok, updated} -> render(conn, :show, warehouse: updated)
          {:error, changeset} -> validation_error(conn, changeset)
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case Warehouses.get(conn.assigns.tenant_id, id) do
      nil ->
        error(conn, :not_found, "WAREHOUSE_NOT_FOUND", "La bodega no existe")

      warehouse ->
        case Warehouses.soft_delete(warehouse) do
          {:ok, _warehouse} ->
            send_resp(conn, :no_content, "")

          {:error, :default_warehouse} ->
            error(
              conn,
              :conflict,
              "DEFAULT_WAREHOUSE",
              "La bodega por defecto no se puede borrar; cree otra y cambie la operacion"
            )

          {:error, :warehouse_not_empty} ->
            error(
              conn,
              :conflict,
              "WAREHOUSE_NOT_EMPTY",
              "La bodega tiene existencia: traslade o ajuste el inventario primero"
            )
        end
    end
  end

  defp validation_error(conn, changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "VALIDATION_ERROR", message: inspect(changeset.errors)})
  end

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{code: code, message: message})
  end
end
