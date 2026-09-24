defmodule KuboErp.Repo.Migrations.CreateOutboxEvents do
  use Ecto.Migration

  @moduledoc """
  Bandeja transaccional de salida (transactional outbox).

  El evento se guarda en la MISMA transaccion de la venta: si la venta se
  confirma, su evento tambien. Un publicador de barrido lo entrega despues a
  RabbitMQ con al-menos-una-entrega (los consumidores deduplican por event_id).
  """

  def change do
    create table(:outbox_events, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:event_id, :binary_id, null: false)
      add(:event_type, :string, size: 80, null: false)
      add(:tenant_id, :binary_id, null: false)
      add(:payload, :map, null: false)
      add(:status, :string, size: 20, null: false, default: "PENDING")
      add(:attempts, :integer, null: false, default: 0)
      add(:available_at, :utc_datetime_usec, null: false)
      add(:published_at, :utc_datetime_usec)
      add(:last_error, :string, size: 500)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:outbox_events, [:event_id], name: :outbox_events_event_id_unique))
    create(index(:outbox_events, [:status, :available_at]))

    create(
      constraint(:outbox_events, :outbox_events_status_check,
        check: "status IN ('PENDING', 'PUBLISHED', 'FAILED')"
      )
    )
  end
end
