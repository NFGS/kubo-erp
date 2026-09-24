defmodule KuboErpWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use KuboErpWeb, :controller
      use KuboErpWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      import Plug.Conn

      unquote(verified_routes())

      # Interceptor de tenant (P-02): cada accion de negocio corre dentro de una
      # transaccion con `app.tenant_id` fijado, de modo que la politica de RLS
      # filtre por negocio aunque una consulta olvide el `where`. Las acciones
      # publicas (sonda de salud) no traen tenant y se ejecutan sin transaccion.
      def action(conn, _opts) do
        case conn.assigns[:tenant_id] do
          nil ->
            apply(__MODULE__, action_name(conn), [conn, conn.params])

          tenant_id ->
            result =
              KuboErp.Repo.transaction(fn ->
                KuboErp.Repo.query!("select set_config('app.tenant_id', $1, true)", [tenant_id])
                apply(__MODULE__, action_name(conn), [conn, conn.params])
              end)

            case result do
              {:ok, conn} ->
                conn

              {:error, reason} when conn.state == :sent ->
                # El controlador ya respondio (por ejemplo, un 409 de negocio) y
                # su rollback aborto la transaccion externa: la respuesta es
                # valida y no hay nada que revertir.
                require Logger

                Logger.warning(
                  "Transaccion de tenant revertida tras responder: #{inspect(reason)}"
                )

                conn

              {:error, reason} ->
                raise "transaccion de tenant fallida: #{inspect(reason)}"
            end
        end
      end
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: KuboErpWeb.Endpoint,
        router: KuboErpWeb.Router,
        statics: KuboErpWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
