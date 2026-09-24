defmodule KuboErp.Notifications.Summarizer do
  @moduledoc """
  Resumen diario del negocio (P-19, ADR-0017).

  Al cerrar el dia comercial (hora configurable en la zona del negocio) encola
  un aviso por cada negocio que vendio, con las ventas del dia. Es un proceso
  **de sistema** —cruce de negocios con la marca `app.system`— y es
  **idempotente**: si el resumen de hoy ya existe, no lo repite, asi que un
  reinicio del servicio a la hora del cierre no duplica el aviso.

  La zona horaria sale de la configuracion del despliegue: el ERP no conoce la
  tabla de negocios de IAM (database-per-service). Los negocios se listan desde
  `tenant_counters` —la unica tabla sin RLS, porque el publicador la necesita—
  y despues se fija el contexto de cada negocio para leer sus ventas: la marca
  de sistema solo abre `notifications`, no las tablas de negocio.
  """

  use GenServer

  require Logger

  import Ecto.Query

  alias KuboErp.{Notifications, Repo, Sales}
  alias KuboErp.Notifications.Notification

  @check_ms 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Ejecuta el resumen de hoy (disparo manual o programado)."
  def run_today do
    Repo.checkout(fn -> resumir_negocios() end)
  end

  @doc """
  Resume los negocios con ventas.

  Se expone aparte del barrido para las pruebas: asi no abre una conexion propia
  (que romperia el aislamiento del sandbox) y el llamador decide el contexto.
  """
  def resumir_negocios do
    timezone = Sales.business_timezone()
    hoy = hoy(timezone)

    negocios_con_ventas()
    |> Enum.each(&resumir(&1, hoy, timezone))
  end

  @impl true
  def init(_opts) do
    schedule()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check, state) do
    if hora_del_resumen?() do
      run_today()
    end

    schedule()
    {:noreply, state}
  end

  defp resumir(tenant_id, hoy, _timezone) do
    # Las tablas de negocio siguen aisladas por RLS: se fija el contexto del
    # negocio (como el interceptor de la peticion) para leer sus ventas.
    Repo.query!("select set_config('app.tenant_id', $1, false)", [tenant_id])

    try do
      if ya_resumido?(tenant_id, hoy) do
        :ok
      else
        resumen = Sales.stats(tenant_id, Sales.business_timezone())

        if resumen.sales_today_count > 0 do
          Notifications.notify(
            tenant_id,
            "DAILY_SUMMARY",
            "Resumen del dia: #{resumen.sales_today_count} venta(s)",
            "Vendiste #{resumen.sales_today} en #{resumen.sales_today_count} venta(s) hoy.",
            reference_type: "DAY",
            reference_id: nil
          )
        end
      end
    after
      Repo.query!("select set_config('app.tenant_id', '', false)")
    end
  end

  # Idempotencia: un resumen por negocio y dia.
  defp ya_resumido?(tenant_id, hoy) do
    desde = DateTime.new!(hoy, ~T[00:00:00], "Etc/UTC")

    Repo.exists?(
      from(n in Notification,
        where:
          n.tenant_id == ^tenant_id and n.kind == "DAILY_SUMMARY" and
            n.inserted_at >= ^desde
      )
    )
  end

  # `tenant_counters` es la unica tabla sin RLS (el publicador la necesita):
  # tiene una fila por negocio que alguna vez vendio o compro.
  defp negocios_con_ventas do
    %{rows: filas} = Repo.query!("select distinct tenant_id from tenant_counters")
    Enum.map(filas, fn [id] -> Ecto.UUID.load!(id) end)
  end

  defp hora_del_resumen? do
    hora = Application.get_env(:kubo_erp, :daily_summary_hour, 20)

    case DateTime.now(Sales.business_timezone()) do
      {:ok, ahora} -> ahora.hour == hora
      {:error, _razon} -> false
    end
  end

  defp hoy(timezone) do
    case DateTime.now(timezone) do
      {:ok, ahora} -> DateTime.to_date(ahora)
      {:error, _razon} -> Date.utc_today()
    end
  end

  defp schedule, do: Process.send_after(self(), :check, @check_ms)
end
