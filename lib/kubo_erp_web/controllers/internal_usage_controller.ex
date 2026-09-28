defmodule KuboErpWeb.InternalUsageController do
  @moduledoc """
  Uso agregado para el panel de plataforma (ADR-0025).

  Sin plug de identidad: la proteccion es la malla (mTLS) y el camino no existe
  en el enrutador publico (Caddy solo publica el gateway). Recibe los negocios
  del gateway —que los obtuvo de IAM— y devuelve solo conteos.
  """

  use KuboErpWeb, :controller

  alias KuboErp.InternalUsage

  @max_tenants 200

  def index(conn, %{"tenant_ids" => ids}) do
    negocios =
      ids
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&uuid?/1)
      |> Enum.uniq()
      |> Enum.take(@max_tenants)

    json(conn, %{data: InternalUsage.for_tenants(negocios)})
  end

  def index(conn, _params) do
    json(conn, %{data: []})
  end

  defp uuid?(valor) do
    match?({:ok, _}, Ecto.UUID.cast(valor))
  end
end
