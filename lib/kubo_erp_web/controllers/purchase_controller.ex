defmodule KuboErpWeb.PurchaseController do
  @moduledoc "Registro, consulta y anulacion de compras (P-15)."

  use KuboErpWeb, :controller

  alias KuboErp.{Pagination, Purchases}

  def index(conn, params) do
    {limit, offset} = Pagination.normalize(params)
    status = params["status"]
    supplier_id = params["supplier_id"]

    purchases =
      Purchases.list(conn.assigns.tenant_id,
        status: status,
        supplier_id: supplier_id,
        limit: limit,
        offset: offset
      )

    total = Purchases.count(conn.assigns.tenant_id, status: status, supplier_id: supplier_id)

    render(conn, :index, purchases: purchases, total: total, limit: limit, offset: offset)
  end

  def stats(conn, _params) do
    render(conn, :stats, stats: Purchases.stats(conn.assigns.tenant_id))
  end

  def show(conn, %{"id" => id}) do
    case Purchases.get(conn.assigns.tenant_id, id) do
      nil -> error(conn, :not_found, "PURCHASE_NOT_FOUND", "La compra no existe")
      purchase -> render(conn, :show, purchase: purchase)
    end
  end

  def create(conn, params) do
    attrs = params["purchase"] || params

    case Purchases.create(conn.assigns.tenant_id, conn.assigns.user_id, attrs) do
      {:ok, purchase} ->
        conn |> put_status(:created) |> render(:show, purchase: purchase)

      {:error, :empty_items} ->
        error(
          conn,
          :unprocessable_entity,
          "EMPTY_PURCHASE",
          "La compra debe incluir al menos un producto"
        )

      {:error, :supplier_not_found} ->
        error(conn, :unprocessable_entity, "SUPPLIER_NOT_FOUND", "El proveedor no existe")

      {:error, :warehouse_not_found} ->
        error(conn, :not_found, "WAREHOUSE_NOT_FOUND", "La bodega no existe")

      {:error, :product_not_found} ->
        error(
          conn,
          :unprocessable_entity,
          "PRODUCT_NOT_FOUND",
          "Alguno de los productos no existe"
        )

      {:error, changeset} ->
        error(conn, :unprocessable_entity, "VALIDATION_ERROR", inspect(changeset.errors))
    end
  end

  def void(conn, %{"id" => id}) do
    case Purchases.void(conn.assigns.tenant_id, conn.assigns.user_id, id) do
      {:ok, purchase} ->
        render(conn, :show, purchase: purchase)

      {:error, :not_found} ->
        error(conn, :not_found, "PURCHASE_NOT_FOUND", "La compra no existe")

      {:error, :already_voided} ->
        error(conn, :conflict, "ALREADY_VOIDED", "La compra ya estaba anulada")

      {:error, reason} ->
        error(conn, :unprocessable_entity, "VOID_FAILED", inspect(reason))
    end
  end

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{code: code, message: message})
  end
end
