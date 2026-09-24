defmodule KuboErp.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  @moduledoc """
  Buzon de notificaciones del negocio (P-19, ADR-0017).

  Guarda lo que el negocio debe saber —stock bajo, resumen de venta— y por que
  canal salio. El envio real es un puerto: el adaptador por defecto escribe en
  este buzon (demostracion) y un proveedor de WhatsApp o correo se enchufa sin
  tocar el nucleo.
  """

  @tenant "NULLIF(current_setting('app.tenant_id', true), '')::uuid"

  def up do
    create table(:notifications, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, :binary_id, null: false)
      add(:kind, :string, size: 40, null: false)
      add(:channel, :string, size: 20, null: false, default: "LOG")
      add(:recipient, :string, size: 180)
      add(:subject, :string, size: 200, null: false)
      add(:body, :text, null: false)
      add(:status, :string, size: 20, null: false, default: "SENT")
      add(:reference_type, :string, size: 20)
      add(:reference_id, :binary_id)
      add(:sent_at, :utc_datetime)

      timestamps(type: :utc_datetime)
    end

    create(index(:notifications, [:tenant_id, :inserted_at]))
    create(index(:notifications, [:tenant_id, :kind]))

    execute("ALTER TABLE notifications ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE notifications FORCE ROW LEVEL SECURITY")

    execute("""
    CREATE POLICY notifications_tenant_isolation ON notifications
      USING (tenant_id = #{@tenant})
      WITH CHECK (tenant_id = #{@tenant})
    """)
  end

  def down do
    execute("DROP POLICY IF EXISTS notifications_tenant_isolation ON notifications")
    execute("ALTER TABLE notifications NO FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE notifications DISABLE ROW LEVEL SECURITY")
    drop(table(:notifications))
  end
end
