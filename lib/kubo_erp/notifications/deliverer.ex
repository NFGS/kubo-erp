defmodule KuboErp.Notifications.Deliverer do
  @moduledoc """
  Entregador de notificaciones por barrido (P-19, ADR-0017).

  Cada 5 s toma un lote de avisos `PENDING` y los entrega por el canal
  configurado. Es un proceso **de sistema**: cruza negocios, y para eso fija la
  marca `app.system` en la conexion que usa (la politica de RLS la respeta; el
  camino de la peticion sigue aislado por negocio).

  La entrega es de al-menos-una-vez y con reintentos: si el canal falla, la fila
  vuelve a la cola con el error anotado hasta agotar los intentos, cuando queda
  `FAILED` para que un humano la revise.
  """

  use GenServer

  require Logger

  alias KuboErp.{Notifications, Repo}

  @sweep_ms 5_000
  @batch_size 10

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Despierta al entregador (por ejemplo, justo despues de encolar un aviso)."
  def kick do
    GenServer.cast(__MODULE__, :sweep)
  end

  @impl true
  def init(_opts) do
    schedule()
    {:ok, %{}}
  end

  @impl true
  def handle_cast(:sweep, state) do
    sweep()
    {:noreply, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep()
    schedule()
    {:noreply, state}
  end

  defp sweep do
    # El barrido cruza negocios: se reserva una conexion y se marca como sistema,
    # igual que el interceptor de tenant fija `app.tenant_id` por peticion.
    Repo.checkout(fn ->
      Repo.query!("select set_config('app.system', 'on', false)")

      try do
        resumen = Repo.transaction(fn -> Notifications.deliver_pending(@batch_size) end)

        case resumen do
          {:ok, %{sent: 0, retry: 0, failed: 0}} ->
            :ok

          {:ok, cuenta} ->
            Logger.info("Notificaciones entregadas: #{inspect(cuenta)}")

          {:error, razon} ->
            Logger.warning("Fallo el barrido de notificaciones: #{inspect(razon)}")
        end
      after
        Repo.query!("select set_config('app.system', 'off', false)")
      end
    end)
  end

  defp schedule, do: Process.send_after(self(), :sweep, @sweep_ms)
end
