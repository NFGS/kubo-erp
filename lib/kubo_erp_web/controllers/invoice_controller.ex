defmodule KuboErpWeb.InvoiceController do
  @moduledoc "Factura electronica de una venta (P-18)."

  use KuboErpWeb, :controller

  alias KuboErp.Invoices

  @doc "Emite la factura de la venta (idempotente: si ya existe, la devuelve)."
  def issue(conn, %{"id" => sale_id}) do
    tenant = %{
      id: conn.assigns.tenant_id,
      name: conn.assigns[:tenant_name]
    }

    case Invoices.issue(conn.assigns.tenant_id, sale_id, tenant) do
      {:ok, factura} ->
        conn |> put_status(:created) |> json(%{data: factura_json(factura)})

      {:error, :sale_not_found} ->
        error(conn, :not_found, "SALE_NOT_FOUND", "La venta no existe")

      {:error, :sale_voided} ->
        error(
          conn,
          :conflict,
          "SALE_VOIDED",
          "Una venta anulada no se factura; se emite una nota credito"
        )

      {:error, reason} ->
        error(conn, :unprocessable_entity, "INVOICE_FAILED", inspect(reason))
    end
  end

  def show(conn, %{"id" => sale_id}) do
    case Invoices.get_by_sale(conn.assigns.tenant_id, sale_id) do
      nil ->
        error(conn, :not_found, "INVOICE_NOT_FOUND", "La venta no tiene factura emitida")

      factura ->
        json(conn, %{data: factura_json(factura)})
    end
  end

  defp factura_json(factura) do
    %{
      id: factura.id,
      sale_id: factura.sale_id,
      number: factura.number,
      cufe: factura.cufe,
      qr_url: factura.qr_url,
      provider: factura.provider,
      status: factura.status,
      issued_at: factura.issued_at,
      xml: factura.xml
    }
  end

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{code: code, message: message})
  end
end
