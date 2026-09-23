defmodule KuboErpWeb.StockController do
  @moduledoc "Ajustes de inventario y consulta del kardex."

  use KuboErpWeb, :controller

  alias KuboErp.Catalog

  def index(conn, params) do
    movements = Catalog.list_movements(conn.assigns.tenant_id, params["product_id"])
    render(conn, :movements, movements: movements)
  end

  def adjust(conn, %{"id" => id} = params) do
    attrs = params["movement"] || params

    case Catalog.adjust_stock(conn.assigns.tenant_id, conn.assigns.user_id, id, attrs) do
      {:ok, product, movement} ->
        render(conn, :stock, product: product, movement: movement)

      {:error, :product_not_found} ->
        error(conn, :not_found, "PRODUCT_NOT_FOUND", "El producto no existe")

      {:error, :invalid_quantity} ->
        error(conn, :bad_request, "INVALID_QUANTITY", "La cantidad debe ser un entero mayor que cero")

      {:error, :invalid_kind} ->
        error(conn, :bad_request, "INVALID_KIND", "El tipo debe ser IN, OUT o ADJUST")

      {:error, {:insufficient_stock, product}} ->
        error(
          conn,
          :conflict,
          "INSUFFICIENT_STOCK",
          "Stock insuficiente de #{product.name}: disponible #{product.stock}"
        )

      {:error, changeset} ->
        error(conn, :unprocessable_entity, "VALIDATION_ERROR", inspect(changeset.errors))
    end
  end

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{code: code, message: message})
  end
end
