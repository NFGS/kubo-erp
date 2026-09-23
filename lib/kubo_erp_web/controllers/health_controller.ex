defmodule KuboErpWeb.HealthController do
  @moduledoc "Sonda de salud del servicio y de su base de datos."

  use KuboErpWeb, :controller

  alias KuboErp.Repo

  def show(conn, _params) do
    database =
      try do
        Repo.query!("select 1")
        "UP"
      rescue
        _error -> "DOWN"
      end

    json(conn, %{
      status: if(database == "UP", do: "UP", else: "DEGRADED"),
      service: "kubo-erp",
      db: database,
      events: if(Application.get_env(:kubo_erp, :amqp_url) in [nil, ""], do: "DISABLED", else: "ENABLED"),
      time: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end
end
