defmodule KuboErpWeb.HealthController do
  @moduledoc "Sonda de salud del servicio y de su base de datos."

  use KuboErpWeb, :controller

  alias KuboErp.{Billing, Invoices, Repo}
  alias KuboErp.Events.Outbox

  def show(conn, _params) do
    database =
      try do
        Repo.query!("select 1")
        "UP"
      rescue
        _error -> "DOWN"
      end

    outbox =
      if(database == "UP", do: Outbox.stats(), else: %{pending: nil, published: nil, failed: nil})

    # El operador puede confirmar que adaptador de facturacion esta activo sin
    # entrar al contenedor; si la configuracion es invalida, se reporta.
    billing =
      try do
        %{adapter: Invoices.provider(), environment: Billing.environment()}
      rescue
        error -> %{adapter: "invalid", error: Exception.message(error)}
      end

    json(conn, %{
      status: if(database == "UP", do: "UP", else: "DEGRADED"),
      service: "kubo-erp",
      db: database,
      events:
        if(Application.get_env(:kubo_erp, :amqp_url) in [nil, ""],
          do: "DISABLED",
          else: "ENABLED"
        ),
      outbox: outbox,
      billing: billing,
      time: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end
end
