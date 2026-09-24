defmodule KuboErp.Repo.Migrations.AddDeliveryToNotifications do
  use Ecto.Migration

  @moduledoc """
  Entrega de notificaciones en segundo plano (P-19, ADR-0017).

  El aviso nace `PENDING` dentro de la transaccion de negocio y un entregador de
  barrido lo envia por el canal configurado. Un proveedor lento o caido ya no
  puede frenar —ni revertir— una venta; los intentos y el ultimo error quedan
  registrados para diagnosticar.
  """

  def change do
    alter table(:notifications) do
      add(:attempts, :integer, null: false, default: 0)
      add(:last_error, :string, size: 300)
    end

    # El entregador busca pendientes: indice parcial, que se mantiene pequeño.
    create(
      index(:notifications, [:status, :inserted_at],
        where: "status = 'PENDING'",
        name: :notifications_pending_index
      )
    )
  end
end
