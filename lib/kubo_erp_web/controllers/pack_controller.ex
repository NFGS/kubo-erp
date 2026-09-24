defmodule KuboErpWeb.PackController do
  @moduledoc "Paquetes de configuracion por vertical (P-17, ADR-0013)."

  use KuboErpWeb, :controller

  alias KuboErp.{Catalog, Packs}

  def index(conn, _params) do
    json(conn, %{data: Packs.all()})
  end

  def current(conn, _params) do
    json(conn, %{data: Packs.get(conn.assigns[:tenant_vertical])})
  end

  @doc "Siembra el catalogo de arranque del paquete activo (idempotente)."
  def apply(conn, _params) do
    pack = Packs.get(conn.assigns[:tenant_vertical])
    json(conn, %{data: Catalog.seed_pack(conn.assigns.tenant_id, pack)})
  end
end
