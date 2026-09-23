defmodule KuboErp.Events.Publisher do
  @moduledoc """
  Publica eventos de dominio en RabbitMQ (exchange `kubo.events`, tipo topic).

  **Degradacion elegante**: si el bus no esta disponible, el evento se descarta
  con una advertencia y la operacion de negocio continua. Ninguna venta debe
  fallar porque analitica este caida.

  La entrega garantizada (patron *transactional outbox* + publicacion desde la
  tabla de salida) esta prevista para la fase 2; hoy se publica despues del
  commit y se acepta la perdida eventual del evento.
  """

  use GenServer

  require Logger

  @exchange "kubo.events"
  @reconnect_ms 10_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Encola la publicacion de un evento. Nunca bloquea ni lanza excepciones."
  def publish(event) do
    GenServer.cast(__MODULE__, {:publish, event})
  end

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    state = %{url: Application.get_env(:kubo_erp, :amqp_url), connection: nil, channel: nil}
    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def handle_info(:connect, %{url: url} = state) when url in [nil, ""] do
    Logger.info("Eventos deshabilitados: AMQP_URL no configurada")
    {:noreply, state}
  end

  def handle_info(:connect, %{url: url} = state) do
    case open_channel(url) do
      {:ok, connection, channel} ->
        Logger.info("Publicador de eventos conectado a RabbitMQ")
        {:noreply, %{state | connection: connection, channel: channel}}

      {:error, reason} ->
        Logger.warning(
          "Sin conexion a RabbitMQ (#{inspect(reason)}); reintento en #{@reconnect_ms} ms"
        )

        Process.send_after(self(), :connect, @reconnect_ms)
        {:noreply, %{state | connection: nil, channel: nil}}
    end
  end

  def handle_info({:EXIT, _pid, reason}, state) do
    Logger.warning("Conexion AMQP caida (#{inspect(reason)}); reintentando")
    Process.send_after(self(), :connect, @reconnect_ms)
    {:noreply, %{state | connection: nil, channel: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def handle_cast({:publish, event}, %{channel: nil} = state) do
    Logger.warning("Evento descartado (sin bus disponible): #{event["event_type"]}")
    {:noreply, state}
  end

  def handle_cast({:publish, event}, %{channel: channel} = state) do
    payload = Jason.encode!(event)

    case AMQP.Basic.publish(channel, @exchange, event["event_type"], payload,
           persistent: true,
           content_type: "application/json"
         ) do
      :ok ->
        Logger.info("Evento publicado #{event["event_type"]} id=#{event["event_id"]}")

      {:error, reason} ->
        Logger.warning("Fallo al publicar evento: #{inspect(reason)}")
    end

    {:noreply, state}
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
