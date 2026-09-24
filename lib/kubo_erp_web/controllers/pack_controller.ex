defmodule KuboErpWeb.PackController do
  @moduledoc "Paquetes de configuracion por vertical (P-17, ADR-0013)."

  use KuboErpWeb, :controller

  alias KuboErp.Packs

  def index(conn, _params) do
    json(conn, %{data: Packs.all()})
  end

  def current(conn, _params) do
    json(conn, %{data: Packs.get(conn.assigns[:tenant_vertical])})
  end
end
