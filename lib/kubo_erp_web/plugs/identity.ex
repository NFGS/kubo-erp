defmodule KuboErpWeb.Plugs.Identity do
  @moduledoc """
  Extrae la identidad que el API Gateway ya verifico.

  Este servicio no valida firmas: solo es alcanzable en la red privada de
  contenedores y el gateway elimina cualquier cabecera `X-User-*` enviada por el
  cliente antes de inyectar la identidad real.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    tenant_id = header(conn, "x-tenant-id")
    user_id = header(conn, "x-user-id")

    if present?(tenant_id) do
      conn
      |> assign(:tenant_id, tenant_id)
      |> assign(:user_id, user_id)
      |> assign(:user_role, header(conn, "x-user-role"))
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{code: "UNAUTHENTICATED", message: "La peticion no trae identidad verificada"})
      |> halt()
    end
  end

  defp header(conn, name) do
    conn |> get_req_header(name) |> List.first()
  end

  defp present?(value), do: is_binary(value) and value != ""
end
