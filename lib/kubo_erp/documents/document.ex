defmodule KuboErp.Documents.Document do
  @moduledoc "Documento del negocio (P-25, ADR-0018): metadatos; los bytes van al almacenamiento."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "documents" do
    field(:tenant_id, :binary_id)
    field(:kind, :string)
    field(:filename, :string)
    field(:content_type, :string)
    field(:size, :integer)
    field(:sha256, :string)
    field(:storage_key, :string)
    field(:reference_type, :string)
    field(:reference_id, :binary_id)
    field(:created_by, :binary_id)

    timestamps(type: :utc_datetime)
  end

  def changeset(document, attrs) do
    document
    |> cast(attrs, [
      :id,
      :tenant_id,
      :kind,
      :filename,
      :content_type,
      :size,
      :sha256,
      :storage_key,
      :reference_type,
      :reference_id,
      :created_by
    ])
    |> validate_required([
      :tenant_id,
      :kind,
      :filename,
      :content_type,
      :size,
      :sha256,
      :storage_key
    ])
    |> validate_length(:sha256, is: 64)
    |> unique_constraint([:tenant_id, :storage_key], name: :documents_storage_key_unique)
  end
end
