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
    children = [
      KuboErpWeb.Telemetry,
      KuboErp.Repo,
      {Phoenix.PubSub, name: KuboErp.PubSub},
      KuboErp.Events.Publisher,
      KuboErpWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: KuboErp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    KuboErpWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
