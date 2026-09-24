defmodule KuboErp.Events.Outbox do
  @moduledoc """
  Bandeja transaccional de salida.

  **Problema que resuelve**: publicar el evento despues del `commit` deja una
  ventana en la que el proceso puede morir entre la confirmacion de la venta y
  la publicacion. La venta ya se cobro, pero el tablero jamas se enteraria.

  **Solucion**: la venta y su evento se guardan en la MISMA transaccion
  (`enqueue/1` se invoca dentro de ella). El publicador de barrido lee las filas
  `PENDING` con `FOR UPDATE SKIP LOCKED` (seguro aunque haya varias instancias
  del ERP) y las entrega a RabbitMQ. La semantica es de **al-menos-una-entrega**:
  si el proceso muere despues de publicar y antes de marcar la fila, el evento
  se reentrega y el consumidor lo descarta por `event_id` (deduplicacion ya
  existente en analitica).
  """

  import Ecto.Query

  alias KuboErp.Repo
  alias KuboErp.Events.OutboxEvent

  @max_attempts 10
  @max_backoff_seconds 300

  @doc """
  Inserta el evento en la bandeja. Debe llamarse DENTRO de la transaccion de
  negocio: si la transaccion se revierte, el evento desaparece con ella.
  """
  def enqueue(event) do
    %OutboxEvent{}
    |> OutboxEvent.changeset(%{
      event_id: event["event_id"],
      event_type: event["event_type"],
      tenant_id: event["tenant_id"],
      payload: event,
      status: "PENDING",
      attempts: 0,
      available_at: now()
    })
    |> Repo.insert!()
  end

  @doc """
  Toma un lote de eventos listos para publicar y los bloquea.

  `SKIP LOCKED` permite que dos publicadores (o dos instancias del ERP) trabajen
  en paralelo sin pisarse ni esperarse. Debe ejecutarse dentro de una
  transaccion.
  """
  def claim_batch(limit) do
    OutboxEvent
    |> where([e], e.status == "PENDING" and e.available_at <= ^now())
    |> order_by([e], asc: e.available_at, asc: e.inserted_at)
    |> limit(^limit)
    |> lock("FOR UPDATE SKIP LOCKED")
    |> Repo.all()
  end

  @doc "Marca el evento como publicado."
  def mark_published(event) do
    event
    |> OutboxEvent.changeset(%{
      status: "PUBLISHED",
      published_at: now(),
      attempts: event.attempts + 1,
      last_error: nil
    })
    |> Repo.update!()
  end

  @doc """
  Reintenta el evento con espera exponencial, o lo marca `FAILED` si agoto los
  intentos. `FAILED` es terminal y visible en la sonda de salud: un evento que
  no se puede entregar es un incidente, no un detalle.
  """
  def mark_retry(event, reason) do
    attempts = event.attempts + 1

    attrs =
      if attempts >= @max_attempts do
        %{status: "FAILED", attempts: attempts, last_error: truncate(reason)}
      else
        %{
          status: "PENDING",
          attempts: attempts,
          available_at: DateTime.add(now(), backoff_seconds(attempts), :second),
          last_error: truncate(reason)
        }
      end

    event
    |> OutboxEvent.changeset(attrs)
    |> Repo.update!()
  end

  @doc "Espera exponencial en segundos, acotada para no crecer sin limite."
  def backoff_seconds(attempts) when is_integer(attempts) and attempts > 0 do
    min(round(:math.pow(2, attempts)), @max_backoff_seconds)
  end

  @doc "Estado de la bandeja para la sonda de salud y la prueba de humo."
  def stats do
    %{
      pending: count("PENDING"),
      published: count("PUBLISHED"),
      failed: count("FAILED")
    }
  end

  defp count(status) do
    Repo.aggregate(from(e in OutboxEvent, where: e.status == ^status), :count)
  end

  defp truncate(nil), do: nil
  defp truncate(reason) when is_binary(reason), do: String.slice(reason, 0, 500)
  defp truncate(reason), do: reason |> inspect() |> String.slice(0, 500)

  defp now, do: DateTime.utc_now()
end
