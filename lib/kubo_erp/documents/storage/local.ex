defmodule KuboErp.Documents.Storage.Local do
  @moduledoc """
  Almacenamiento en el sistema de archivos (ADR-0018).

  La raiz se configura con `KUBO_DOCUMENTS_PATH` y debe ser un volumen del
  despliegue: entra en el respaldo junto con la base. La clave la genera el
  contexto (`tenant_id/uuid`), nunca el usuario; aun asi se rechaza cualquier
  clave que intente salir de la raiz.
  """

  @behaviour KuboErp.Documents.Storage

  @impl true
  def put(key, content) do
    path = path_for(key)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, content) do
      :ok
    end
  end

  @impl true
  def get(key), do: File.read(path_for(key))

  @impl true
  def delete(key), do: File.rm(path_for(key))

  defp path_for(key) do
    if String.contains?(key, "..") or String.starts_with?(key, "/") do
      raise ArgumentError, "clave de documento invalida"
    end

    Path.join(base(), key)
  end

  defp base, do: Application.get_env(:kubo_erp, :documents_path, "priv/documents")
end
