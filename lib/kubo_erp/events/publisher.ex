defmodule KuboErp.Events.Publisher do
  @moduledoc """
  Publicador de barrido de la bandeja de salida.

  Cada 500 ms (o cuando una venta lo despierta con `kick/0`) toma un lote de
  eventos `PENDING` y los entrega a RabbitMQ (exchange `kubo.events`, tipo
  topic). Si el bus esta caido, los eventos **permanecen en la bandeja**: no se
  pierden ni bloquean la caja, y se entregan cuando la conexion vuelve.

  La conexion se **monitorea**: si el proceso de AMQP muere (contenedor
  detenido, red cortada), el publicador vuelve a estado desconectado y reintenta
  cada 10 s. Sin el monitor, el canal quedaria muerto en memoria y cada barrido
  fallaria con `:noproc` sin reconectar.

  La entrega es de al-menos-una-vez: si el proceso muere despues de publicar y
  antes de marcar la fila, el evento se reentrega. Los consumidores deduplican
  por `event_id` (analitica ya lo hace con su indice unico en MongoDB).
  """

  use GenServer

  require Logger

  alias KuboErp.Events.Outbox
  alias KuboErp.Repo

  @exchange "kubo.events"
  @reconnect_ms 10_000
  @sweep_ms 500
  @batch_size 25

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Despierta al publicador despues de confirmar una transaccion de negocio."
  def kick do
    GenServer.cast(__MODULE__, :sweep)
  end

  @impl true
  def init(_opts) do
    state = %{
      url: Application.get_env(:kubo_erp, :amqp_url),
      connection: nil,
      channel: nil,
      connection_ref: nil
    }

    send(self(), :connect)
    schedule_sweep()
    {:ok, state}
  end

  @impl true
  def handle_cast(:sweep, state), do: {:noreply, sweep(state)}

  @impl true
  def handle_info(:sweep, state) do
    schedule_sweep()
    {:noreply, sweep(state)}
  end

  def handle_info(:connect, %{url: url} = state) when url in [nil, ""] do
    Logger.info("Eventos deshabilitados: AMQP_URL no configurada")
    {:noreply, state}
  end

  def handle_info(:connect, %{channel: channel} = state) when not is_nil(channel) do
    {:noreply, state}
  end

  def handle_info(:connect, %{url: url} = state) do
    case open_channel(url) do
      {:ok, connection, channel} ->
        Logger.info("Publicador de eventos conectado a RabbitMQ")

        state = %{
          state
          | connection: connection,
            channel: channel,
            connection_ref: Process.monitor(connection.pid)
        }

        {:noreply, sweep(state)}

      {:error, reason} ->
        Logger.warning(
          "Sin conexion a RabbitMQ (#{inspect(reason)}); reintento en #{@reconnect_ms} ms"
        )

        schedule_connect()
        {:noreply, %{state | connection: nil, channel: nil, connection_ref: nil}}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{connection_ref: ref} = state) do
    Logger.warning("Conexion AMQP caida (#{inspect(reason)}); reintentando")
    schedule_connect()
    {:noreply, %{state | connection: nil, channel: nil, connection_ref: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_ms)
  defp schedule_connect, do: Process.send_after(self(), :connect, @reconnect_ms)

  # Sin canal no se toca la bandeja: los eventos quedan PENDING y esperan.
  defp sweep(%{channel: nil} = state), do: state

  defp sweep(%{channel: channel} = state) do
    try do
      Repo.transaction(fn ->
        @batch_size
        |> Outbox.claim_batch()
        |> Enum.each(&deliver(&1, channel))
      end)

      state
    rescue
      error ->
        Logger.warning("Barrido de la bandeja fallo: #{inspect(error)}")
        state
    catch
      :exit, reason ->
        Logger.warning("Canal AMQP no disponible (#{inspect(reason)}); reconectando")
        schedule_connect()
        %{state | connection: nil, channel: nil, connection_ref: nil}
    end
  end

  defp deliver(event, channel) do
    payload = Jason.encode!(event.payload)

    case AMQP.Basic.publish(channel, @exchange, event.event_type, payload,
           persistent: true,
           content_type: "application/json"
         ) do
      :ok ->
        Outbox.mark_published(event)
        Logger.info("Evento publicado #{event.event_type} id=#{event.event_id}")

      {:error, reason} ->
        Outbox.mark_retry(event, inspect(reason))
        Logger.warning("Fallo al publicar #{event.event_type}: #{inspect(reason)}")
    end
  end

  defp open_channel(url) do
    with {:ok, connection} <- AMQP.Connection.open(url),
         {:ok, channel} <- AMQP.Channel.open(connection),
         :ok <- AMQP.Exchange.declare(channel, @exchange, :topic, durable: true) do
      {:ok, connection, channel}
    end
  rescue
    error -> {:error, error}
  end
end
