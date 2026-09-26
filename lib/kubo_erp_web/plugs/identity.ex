defmodule KuboErpWeb.Plugs.Identity do
  @moduledoc """
  Extrae la identidad que el API Gateway ya verifico.

  Este servicio no valida firmas: solo es alcanzable en la red privada de
  contenedores y el gateway elimina cualquier cabecera `X-User-*` enviada por el
  cliente antes de inyectar la identidad real.

  Ademas del control de presencia, se valida el **formato UUID** de las
  cabeceras: un valor malformado no debe llegar a `set_config('app.tenant_id')`
  ni a la numeracion, donde provocaria un error de conversion (500) en lugar de
  una respuesta clara.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @uuid_regex ~r/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/

  def init(opts), do: opts

  def call(conn, _opts) do
    tenant_id = header(conn, "x-tenant-id")
    user_id = header(conn, "x-user-id")
    timezone = header(conn, "x-tenant-timezone")

    cond do
      not present?(tenant_id) ->
        error(conn, :unauthorized, "UNAUTHENTICATED", "La peticion no trae identidad verificada")

      not Regex.match?(@uuid_regex, tenant_id) ->
        error(conn, :bad_request, "INVALID_TENANT", "El negocio indicado no es valido")

      present?(user_id) and not Regex.match?(@uuid_regex, user_id) ->
        error(conn, :bad_request, "INVALID_USER", "El usuario indicado no es valido")

      # Una zona desconocida haria caer el dia comercial a UTC en silencio: se
      # rechaza en la puerta (ADR-0012). Ausente es valido: aplica el respaldo.
      present?(timezone) and not timezone_valida?(timezone) ->
        error(conn, :bad_request, "INVALID_TIMEZONE", "La zona horaria del negocio no es valida")

      true ->
        conn
        |> assign(:tenant_id, tenant_id)
        |> assign(:user_id, user_id)
        |> assign(:user_role, header(conn, "x-user-role"))
        |> assign(:tenant_timezone, timezone)
        |> assign(:tenant_vertical, header(conn, "x-tenant-vertical"))
        |> assign(:tenant_name, header(conn, "x-tenant-name"))
        |> assign(:tenant_plan, header(conn, "x-tenant-plan"))
    end
  end

  # La base de zonas se carga al arrancar (tzdata); si no conoce el nombre, no es
  # una zona IANA valida.
  defp timezone_valida?(valor) do
    match?({:ok, _ahora}, DateTime.now(valor))
  end

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{code: code, message: message}) |> halt()
  end

  defp header(conn, name) do
    conn |> get_req_header(name) |> List.first()
  end

  defp present?(value), do: is_binary(value) and value != ""
end
