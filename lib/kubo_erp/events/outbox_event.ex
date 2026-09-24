defmodule KuboErp.Events.OutboxEvent do
  @moduledoc """
  Fila de la bandeja de salida: un evento de dominio pendiente de publicar.

  `payload` guarda el sobre completo (el mismo que recibe el consumidor) para
  que la publicacion sea una simple relectura, sin reconstruir el evento.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "outbox_events" do
    field(:event_id, :binary_id)
    field(:event_type, :string)
    field(:tenant_id, :binary_id)
    field(:payload, :map)
    field(:status, :string, default: "PENDING")
    field(:attempts, :integer, default: 0)
    field(:available_at, :utc_datetime_usec)
    field(:published_at, :utc_datetime_usec)
    field(:last_error, :string)

    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :event_id,
      :event_type,
      :tenant_id,
      :payload,
      :status,
      :attempts,
      :available_at,
      :published_at,
      :last_error
    ])
    |> validate_required([:event_id, :event_type, :tenant_id, :payload, :status, :available_at])
    |> validate_inclusion(:status, ["PENDING", "PUBLISHED", "FAILED"])
  end
end
