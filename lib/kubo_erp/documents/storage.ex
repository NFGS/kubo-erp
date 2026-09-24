defmodule KuboErp.Documents.Storage do
  @moduledoc """
  Puerto de almacenamiento de documentos (ADR-0018).

  El adaptador por defecto escribe en el sistema de archivos; un bucket (S3,
  Cloudinary) implementa este contrato sin tocar el contexto.
  """

  @callback put(key :: String.t(), content :: binary()) :: :ok | {:error, term()}
  @callback get(key :: String.t()) :: {:ok, binary()} | {:error, term()}
  @callback delete(key :: String.t()) :: :ok | {:error, term()}
end
