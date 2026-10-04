defmodule KuboErpWeb.InvoiceController do
  @moduledoc "Factura electronica de una venta (P-18)."

  use KuboErpWeb, :controller

  alias KuboErp.Invoices
  alias KuboErpWeb.BillingErrors

  @doc "Emite la factura de la venta (idempotente: si ya existe, la devuelve)."
  def issue(conn, %{"id" => sale_id}) do
    case Invoices.issue(conn.assigns.tenant_id, sale_id, tenant(conn)) do
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

      {:error, razon} ->
        BillingErrors.responder(conn, razon)
    end
  end

  @doc """
  Consulta el estado en linea del documento (proveedores con validacion
  asincrona). El sandbox no lo implementa y responde 501.
  """
  def refresh(conn, %{"id" => invoice_id}) do
    case Invoices.refresh_status(conn.assigns.tenant_id, invoice_id) do
      {:ok, factura} ->
        json(conn, %{data: factura_json(factura)})

      {:error, :invoice_not_found} ->
        error(conn, :not_found, "INVOICE_NOT_FOUND", "La factura no existe")

      {:error, razon} ->
        BillingErrors.responder(conn, razon)
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

  # El negocio viaja con sus datos fiscales (DIAN): el adaptador los necesita
  # sin consultar a IAM; el gateway los propaga verificados desde el token.
  defp tenant(conn) do
    %{
      id: conn.assigns.tenant_id,
      name: conn.assigns[:tenant_name],
      tax_id: conn.assigns[:tenant_tax_id],
      tax_id_dv: conn.assigns[:tenant_tax_id_dv],
      fiscal_address: conn.assigns[:tenant_fiscal_address],
      tax_regime: conn.assigns[:tenant_tax_regime],
      invoice_resolution: conn.assigns[:tenant_invoice_resolution],
      invoice_prefix: conn.assigns[:tenant_invoice_prefix]
    }
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
      status_detail: factura.status_detail,
      provider_reference: factura.provider_reference,
      issued_at: factura.issued_at,
      xml: factura.xml
    }
  end

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{code: code, message: message})
  end
end
