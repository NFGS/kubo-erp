defmodule KuboErpWeb.DocumentController do
  @moduledoc "Documentos del negocio (P-25, ADR-0018)."

  use KuboErpWeb, :controller

  alias KuboErp.Documents

  def index(conn, _params) do
    render(conn, :index, documents: Documents.list(conn.assigns.tenant_id))
  end

  @doc "Descarga el documento con su tipo de contenido."
  def show(conn, %{"id" => id}) do
    case Documents.get(conn.assigns.tenant_id, id) do
      nil ->
        error(conn, :not_found, "DOCUMENT_NOT_FOUND", "El documento no existe")

      document ->
        case Documents.content(document) do
          {:ok, contenido} ->
            conn
            |> put_resp_content_type(document.content_type)
            |> put_resp_header(
              "content-disposition",
              "attachment; filename=\"#{document.filename}\""
            )
            |> send_resp(200, contenido)

          {:error, _razon} ->
            error(
              conn,
              :not_found,
              "DOCUMENT_CONTENT_NOT_FOUND",
              "El contenido del documento no esta disponible"
            )
        end
    end
  end

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{code: code, message: message})
  end
end
