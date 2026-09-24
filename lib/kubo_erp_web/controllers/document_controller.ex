defmodule KuboErpWeb.DocumentController do
  @moduledoc "Documentos del negocio (P-25, ADR-0018)."

  use KuboErpWeb, :controller

  alias KuboErp.{Documents, Purchases}

  # Soportes aceptados (P-25): documentos y fotos del soporte fisico.
  @extensiones ~w[pdf xml png jpg jpeg webp]
  @max_bytes 5_000_000

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

  @doc """
  Adjunta un soporte a una compra (P-25).

  El archivo viaja como multipart; se guarda por el puerto de almacenamiento y
  queda ligado a la compra, que es el hecho de negocio que lo origina.
  """
  def create_for_purchase(conn, %{"id" => purchase_id} = params) do
    case Purchases.get(conn.assigns.tenant_id, purchase_id) do
      nil ->
        error(conn, :not_found, "PURCHASE_NOT_FOUND", "La compra no existe")

      purchase ->
        adjuntar(conn, purchase, params)
    end
  end

  defp adjuntar(conn, purchase, params) do
    with {:ok, upload} <- validar_archivo(params["file"]),
         {:ok, documento} <-
           Documents.store(conn.assigns.tenant_id, %{
             kind: "PURCHASE_SUPPORT",
             filename: upload.filename,
             content_type: upload.content_type || "application/octet-stream",
             content: File.read!(upload.path),
             reference_type: "PURCHASE",
             reference_id: purchase.id,
             created_by: conn.assigns.user_id
           }) do
      conn |> put_status(:created) |> render(:show, document: documento)
    else
      {:error, :no_file} ->
        error(conn, :unprocessable_entity, "FILE_REQUIRED", "Adjunte el archivo en el campo file")

      {:error, :invalid_extension} ->
        error(
          conn,
          :unprocessable_entity,
          "INVALID_EXTENSION",
          "Solo se aceptan soportes #{Enum.join(@extensiones, ", ")}"
        )

      {:error, :too_large} ->
        error(conn, :unprocessable_entity, "FILE_TOO_LARGE", "El soporte supera 5 MB")

      {:error, changeset} ->
        error(conn, :unprocessable_entity, "DOCUMENT_FAILED", inspect(changeset.errors))
    end
  end

  defp validar_archivo(%Plug.Upload{} = upload) do
    extension = upload.filename |> Path.extname() |> String.trim_leading(".") |> String.downcase()
    tamano = File.stat!(upload.path).size

    cond do
      extension not in @extensiones -> {:error, :invalid_extension}
      tamano > @max_bytes -> {:error, :too_large}
      true -> {:ok, upload}
    end
  end

  defp validar_archivo(_params), do: {:error, :no_file}

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{code: code, message: message})
  end
end
