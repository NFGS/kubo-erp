defmodule KuboErpWeb.ReportController do
  @moduledoc "Reportes exportables en CSV (P-21)."

  use KuboErpWeb, :controller

  alias KuboErp.Reports

  def sales(conn, params) do
    responder(conn, Reports.sales_csv(conn.assigns.tenant_id, params), "ventas.csv")
  end

  def inventory(conn, _params) do
    responder(conn, Reports.inventory_csv(conn.assigns.tenant_id), "inventario.csv")
  end

  defp responder(conn, {:ok, contenido}, nombre) do
    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", "attachment; filename=\"#{nombre}\"")
    |> send_resp(200, contenido)
  end

  defp responder(conn, {:error, {:invalid_date, mensaje}}, _nombre) do
    conn
    |> put_status(:bad_request)
    |> json(%{code: "INVALID_DATE_RANGE", message: mensaje})
  end

  defp responder(conn, {:error, {:too_large, mensaje}}, _nombre) do
    conn
    |> put_status(:bad_request)
    |> json(%{code: "REPORT_TOO_LARGE", message: mensaje})
  end
end
