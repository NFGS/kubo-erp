defmodule KuboErpWeb.TransferController do
  @moduledoc "Transferencias entre bodegas (P-22, ADR-0016)."

  use KuboErpWeb, :controller

  alias KuboErp.Transfers

  def index(conn, _params) do
    render(conn, :index, transfers: Transfers.list(conn.assigns.tenant_id))
  end

  def show(conn, %{"id" => id}) do
    case Transfers.get(conn.assigns.tenant_id, id) do
      nil -> error(conn, :not_found, "TRANSFER_NOT_FOUND", "La transferencia no existe")
      transfer -> render(conn, :show, transfer: transfer)
    end
  end

  def create(conn, params) do
    case Transfers.create(conn.assigns.tenant_id, conn.assigns.user_id, params) do
      {:ok, transfer} ->
        conn |> put_status(:created) |> render(:show, transfer: transfer)

      {:error, :empty_items} ->
        error(conn, :unprocessable_entity, "EMPTY_TRANSFER", "La transferencia no trae productos")

      {:error, :same_warehouse} ->
        error(
          conn,
          :unprocessable_entity,
          "SAME_WAREHOUSE",
          "El origen y el destino deben ser bodegas distintas"
        )

      {:error, :origin_not_found} ->
        error(conn, :not_found, "ORIGIN_NOT_FOUND", "La bodega de origen no existe")

      {:error, :destination_not_found} ->
        error(conn, :not_found, "DESTINATION_NOT_FOUND", "La bodega de destino no existe")

      {:error, :product_not_found} ->
        error(
          conn,
          :unprocessable_entity,
          "PRODUCT_NOT_FOUND",
          "Alguno de los productos no existe"
        )

      {:error, :product_without_stock} ->
        error(
          conn,
          :unprocessable_entity,
          "PRODUCT_WITHOUT_STOCK",
          "Un servicio no tiene inventario que trasladar"
        )

      {:error, {:insufficient_stock, product}} ->
        error(
          conn,
          :conflict,
          "INSUFFICIENT_STOCK",
          "Existencia insuficiente de #{product.name} en la bodega de origen"
        )

      {:error, reason} ->
        error(conn, :unprocessable_entity, "TRANSFER_FAILED", inspect(reason))
    end
  end

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{code: code, message: message})
  end
end
