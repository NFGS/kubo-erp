defmodule KuboErpWeb.CreditNoteController do
  @moduledoc "Nota credito electronica de una venta anulada (P-18, ADR-0014)."

  use KuboErpWeb, :controller

  alias KuboErp.CreditNotes

  @doc "Emite la nota credito (idempotente: si ya existe, la devuelve)."
  def issue(conn, %{"id" => sale_id} = params) do
    tenant = %{
      id: conn.assigns.tenant_id,
      name: conn.assigns[:tenant_name]
    }

    razon = params["reason"]

    case CreditNotes.issue(conn.assigns.tenant_id, sale_id, tenant, razon) do
      {:ok, nota} ->
        conn |> put_status(:created) |> json(%{data: nota_json(nota)})

      {:error, :sale_not_found} ->
        error(conn, :not_found, "SALE_NOT_FOUND", "La venta no existe")

      {:error, :sale_not_voided} ->
        error(
          conn,
          :conflict,
          "SALE_NOT_VOIDED",
          "Una nota credito corrige una factura: anula primero la venta"
        )

      {:error, :invoice_not_found} ->
        error(
          conn,
          :conflict,
          "INVOICE_NOT_FOUND",
          "La venta no tiene factura: no hay nada que corregir"
        )

      {:error, reason} ->
        error(conn, :unprocessable_entity, "CREDIT_NOTE_FAILED", inspect(reason))
    end
  end

  def show(conn, %{"id" => sale_id}) do
    case CreditNotes.get_by_sale(conn.assigns.tenant_id, sale_id) do
      nil ->
        error(conn, :not_found, "CREDIT_NOTE_NOT_FOUND", "La venta no tiene nota credito")

      nota ->
        json(conn, %{data: nota_json(nota)})
    end
  end

  defp nota_json(nota) do
    %{
      id: nota.id,
      sale_id: nota.sale_id,
      invoice_id: nota.invoice_id,
      number: nota.number,
      cude: nota.cude,
      qr_url: nota.qr_url,
      reason: nota.reason,
      provider: nota.provider,
      issued_at: nota.issued_at,
      xml: nota.xml
    }
  end

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{code: code, message: message})
  end
end
