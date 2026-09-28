defmodule KuboErp.Documents do
  @moduledoc """
  Documentos del negocio (P-25, ADR-0018).

  Un documento nace como **consecuencia de un hecho de negocio** (la factura
  emitida, mas adelante el soporte de una compra), no de una subida suelta: eso
  deja la trazabilidad cerrada. Los bytes van al almacenamiento (puerto) y los
  metadatos —con el SHA-256 del contenido— a la base, donde los protege la RLS.
  """

  import Ecto.Query

  alias KuboErp.Repo
  alias KuboErp.Documents.Document

  @doc "Almacenamiento configurado (`KUBO_DOCUMENTS_STORAGE`); por defecto, el disco."
  def storage do
    Application.get_env(:kubo_erp, :documents_storage, KuboErp.Documents.Storage.Local)
  end

  @doc """
  Guarda un documento y devuelve su ficha.

  Si la base falla despues de escribir los bytes, se borra el objeto: no se
  dejan huerfanos que nadie pueda reclamar.
  """
  def store(tenant_id, attrs) do
    contenido = attrs.content
    id = Ecto.UUID.generate()
    clave = "#{tenant_id}/#{id}"
    hash = :crypto.hash(:sha256, contenido) |> Base.encode16(case: :lower)

    with :ok <- storage().put(clave, contenido) do
      resultado =
        %Document{}
        |> Document.changeset(%{
          id: id,
          tenant_id: tenant_id,
          kind: attrs.kind,
          filename: attrs.filename,
          content_type: attrs.content_type,
          size: byte_size(contenido),
          sha256: hash,
          storage_key: clave,
          reference_type: attrs[:reference_type],
          reference_id: attrs[:reference_id],
          created_by: attrs[:created_by]
        })
        |> Repo.insert()

      if match?({:error, _changeset}, resultado) do
        storage().delete(clave)
      end

      resultado
    end
  end

  def get(tenant_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        Document
        |> where([d], d.tenant_id == ^tenant_id and d.id == ^uuid)
        |> Repo.one()

      :error ->
        nil
    end
  end

  def list(tenant_id, limit \\ 50) do
    Document
    |> where([d], d.tenant_id == ^tenant_id)
    |> order_by([d], desc: d.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def content(%Document{} = document), do: storage().get(document.storage_key)

  @doc "Uso de almacenamiento del negocio (F6.1): cuantos documentos y cuantos bytes."
  def usage(tenant_id) do
    Document
    |> where([d], d.tenant_id == ^tenant_id)
    |> select([d], %{count: count(d.id), bytes: coalesce(sum(d.size), 0)})
    |> Repo.one()
  end
end
