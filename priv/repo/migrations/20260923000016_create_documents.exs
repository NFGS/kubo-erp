defmodule KuboErp.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  @moduledoc """
  Documentos del negocio (P-25, ADR-0018).

  La fila guarda los **metadatos y la clave** del objeto; los bytes viven en el
  almacenamiento (sistema de archivos por defecto, puerto para un bucket). El
  SHA-256 permite verificar que un documento fiscal no cambio.
  """

  @tenant "NULLIF(current_setting('app.tenant_id', true), '')::uuid"

  def up do
    create table(:documents, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, :binary_id, null: false)
      add(:kind, :string, size: 40, null: false)
      add(:filename, :string, size: 200, null: false)
      add(:content_type, :string, size: 100, null: false)
      add(:size, :integer, null: false)
      add(:sha256, :string, size: 64, null: false)
      add(:storage_key, :string, size: 300, null: false)
      add(:reference_type, :string, size: 20)
      add(:reference_id, :binary_id)
      add(:created_by, :binary_id)

      timestamps(type: :utc_datetime)
    end

    create(index(:documents, [:tenant_id, :inserted_at]))
    create(index(:documents, [:tenant_id, :reference_type, :reference_id]))

    create(
      unique_index(:documents, [:tenant_id, :storage_key], name: :documents_storage_key_unique)
    )

    execute("ALTER TABLE documents ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE documents FORCE ROW LEVEL SECURITY")

    execute("""
    CREATE POLICY documents_tenant_isolation ON documents
      USING (tenant_id = #{@tenant})
      WITH CHECK (tenant_id = #{@tenant})
    """)
  end

  def down do
    execute("DROP POLICY IF EXISTS documents_tenant_isolation ON documents")
    execute("ALTER TABLE documents NO FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE documents DISABLE ROW LEVEL SECURITY")
    drop(table(:documents))
  end
end
