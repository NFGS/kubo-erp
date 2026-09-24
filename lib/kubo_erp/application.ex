defmodule KuboErp.Application do
  @moduledoc """
  Arbol de supervision de kubo-erp.

  El publicador de eventos se arranca antes que el endpoint para que la primera
  venta ya pueda emitir su evento. Si RabbitMQ no esta disponible, el publicador
  no tumba la aplicacion: registra la advertencia y reintenta.
  """

  use Application

  @impl true
  def start(_type, _args) do
    # Zona horaria real del negocio (tzdata). Sin esto, Elixir solo conoce UTC y
    # el calculo del dia comercial caeria silenciosamente a UTC.
    Calendar.put_time_zone_database(Tzdata.TimeZoneDatabase)

    setup_tracing()

    children = [
      KuboErpWeb.Telemetry,
      KuboErp.Repo,
      {Phoenix.PubSub, name: KuboErp.PubSub},
      KuboErp.Events.Publisher,
      KuboErp.Notifications.Deliverer,
      KuboErp.Notifications.Summarizer,
      KuboErpWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: KuboErp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Instrumentacion de trazas (P-07): solo si hay collector configurado. Sin
  # endpoint, la aplicacion no paga el costo de crear spans que nadie recibe.
  # `setup/1` engancha los eventos de telemetria; no son hijos del supervisor.
  defp setup_tracing do
    if System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") do
      OpentelemetryPhoenix.setup(adapter: :bandit)
      OpentelemetryEcto.setup([:kubo_erp, :repo])
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    KuboErpWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
