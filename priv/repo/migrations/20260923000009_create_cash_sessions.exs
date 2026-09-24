defmodule KuboErp.Repo.Migrations.CreateCashSessions do
  use Ecto.Migration

  @moduledoc """
  Sesiones de caja (P-16, Fase 3): apertura, cierre y arqueo.

  Un negocio de barrio abre la caja con una base, vende durante el turno y al
  cerrar cuenta el efectivo. La diferencia entre lo contado y lo esperado es el
  dato que busca el tendero.

  Reglas:
    * Una sola sesion ABIERTA por negocio: indice unico parcial en el motor.
    * Las ventas se ligan a la sesion (`sales.cash_session_id`), de modo que el
      esperado se calcula con las ventas del turno y no por ventanas de tiempo.
    * El esperado = base + ventas en efectivo completadas − ventas anuladas.
  """

  @tenant "NULLIF(current_setting('app.tenant_id', true), '')::uuid"

  def change do
    create table(:cash_sessions, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, :binary_id, null: false)
      add(:status, :string, size: 20, null: false, default: "OPEN")
      add(:opened_by, :binary_id)
      add(:opened_at, :utc_datetime, null: false)
      add(:opening_amount, :decimal, precision: 14, scale: 2, null: false, default: 0)
      add(:closed_by, :binary_id)
      add(:closed_at, :utc_datetime)
      add(:counted_amount, :decimal, precision: 14, scale: 2)
      add(:expected_amount, :decimal, precision: 14, scale: 2)
      add(:difference, :decimal, precision: 14, scale: 2)
      add(:notes, :string, size: 400)

      timestamps(type: :utc_datetime)
    end

    create(index(:cash_sessions, [:tenant_id, :opened_at]))

    # Una sola caja abierta por negocio; el motor lo garantiza.
    create(
      unique_index(:cash_sessions, [:tenant_id],
        where: "status = 'OPEN'",
        name: :cash_sessions_one_open_per_tenant
      )
    )

    create(
      constraint(:cash_sessions, :cash_sessions_status_check,
        check: "status IN ('OPEN', 'CLOSED')"
      )
    )

    alter table(:sales) do
      add(
        :cash_session_id,
        references(:cash_sessions, type: :binary_id, on_delete: :nilify_all)
      )
    end

    create(index(:sales, [:cash_session_id]))

    execute("ALTER TABLE cash_sessions ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE cash_sessions FORCE ROW LEVEL SECURITY")
    execute("DROP POLICY IF EXISTS cash_sessions_tenant_isolation ON cash_sessions")

    execute("""
    CREATE POLICY cash_sessions_tenant_isolation ON cash_sessions
      USING (tenant_id = #{@tenant})
      WITH CHECK (tenant_id = #{@tenant})
    """)
  end
end
