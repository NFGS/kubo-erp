defmodule KuboErpWeb.DocumentJSON do
  @moduledoc "Representacion JSON de documentos (P-25): metadatos, sin los bytes."

  def index(%{documents: documents}), do: %{data: Enum.map(documents, &data/1)}

  def show(%{document: document}), do: %{data: data(document)}

  defp data(document) do
    %{
      id: document.id,
      kind: document.kind,
      filename: document.filename,
      content_type: document.content_type,
      size: document.size,
      sha256: document.sha256,
      reference_type: document.reference_type,
      reference_id: document.reference_id,
      created_at: iso(document.inserted_at)
    }
  end

  defp iso(nil), do: nil
  defp iso(%DateTime{} = valor), do: DateTime.to_iso8601(valor)
  defp iso(%NaiveDateTime{} = valor), do: NaiveDateTime.to_iso8601(valor)
end
