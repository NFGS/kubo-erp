defmodule KuboErpWeb.SaleController do
  @moduledoc "Registro, consulta y anulacion de ventas."

  use KuboErpWeb, :controller

  alias KuboErp.{Pagination, Sales}

  def index(conn, params) do
    {limit, offset} = Pagination.normalize(params)
    status = params["status"]

    sales = Sales.list_sales(conn.assigns.tenant_id, status: status, limit: limit, offset: offset)
    total = Sales.count_sales(conn.assigns.tenant_id, status)

    render(conn, :index, sales: sales, total: total, limit: limit, offset: offset)
  end

  def stats(conn, _params) do
    render(conn, :stats, stats: Sales.stats(conn.assigns.tenant_id))
  end

  def show(conn, %{"id" => id}) do
    case Sales.get_sale(conn.assigns.tenant_id, id) do
      nil -> error(conn, :not_found, "SALE_NOT_FOUND", "La venta no existe")
      sale -> render(conn, :show, sale: sale)
    end
  end

  def create(conn, params) do
    attrs = params["sale"] || params

    case Sales.create_sale(conn.assigns.tenant_id, conn.assigns.user_id, attrs) do
      {:ok, sale} ->
        conn |> put_status(:created) |> render(:show, sale: sale)

      {:error, :empty_items} ->
        error(
          conn,
          :unprocessable_entity,
          "EMPTY_SALE",
          "La venta debe incluir al menos un producto"
        )

      {:error, :product_not_found} ->
        error(
          conn,
          :unprocessable_entity,
          "PRODUCT_NOT_FOUND",
          "Alguno de los productos no existe"
        )

      {:error, {:insufficient_stock, product}} ->
        error(
          conn,
          :conflict,
          "INSUFFICIENT_STOCK",
          "Stock insuficiente de #{product.name}: disponible #{product.stock}"
        )

      {:error, :customer_name_required} ->
        error(
          conn,
          :unprocessable_entity,
          "CUSTOMER_NAME_REQUIRED",
          "Si la venta lleva cliente, debe incluir su nombre (customer_name)"
        )

      {:error, :number_conflict} ->
        error(
          conn,
          :conflict,
          "NUMBER_CONFLICT",
          "No fue posible asignar el numero de venta, reintente"
        )

      {:error, changeset} ->
        error(conn, :unprocessable_entity, "VALIDATION_ERROR", inspect(changeset.errors))
    end
  end

  def void(conn, %{"id" => id}) do
    case Sales.void_sale(conn.assigns.tenant_id, conn.assigns.user_id, id) do
      {:ok, sale} ->
        render(conn, :show, sale: sale)

      {:error, :not_found} ->
        error(conn, :not_found, "SALE_NOT_FOUND", "La venta no existe")

      {:error, :already_voided} ->
        error(conn, :conflict, "ALREADY_VOIDED", "La venta ya estaba anulada")

      {:error, reason} ->
        error(conn, :unprocessable_entity, "VOID_FAILED", inspect(reason))
    end
  end

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{code: code, message: message})
  end
end
