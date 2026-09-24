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

      # Interceptor de tenant (P-02): fija `app.tenant_id` en la conexion que
      # atiende la peticion, de modo que la politica de RLS filtre por negocio
      # aunque una consulta olvide el `where`.
      #
      # Se usa `checkout` (conexion reservada) y no una transaccion externa: en
      # esta version de Ecto, `Repo.rollback` solo es valido en una transaccion
      # real (`conn_mode: :transaction`), no dentro de un savepoint. Envolver la
      # peticion en una transaccion convertiria cada rollback de negocio (stock
      # insuficiente, numero de venta) en una peticion fallida.
      #
      # La marca es de sesion y se limpia siempre en `after`; ademas cada
      # peticion de negocio la vuelve a fijar antes de consultar, de modo que un
      # valor filtrado por una muerte abrupta no puede afectar a otra peticion.
      def action(conn, _opts) do
        case conn.assigns[:tenant_id] do
          nil ->
            apply(__MODULE__, action_name(conn), [conn, conn.params])

          tenant_id ->
            KuboErp.Repo.checkout(fn ->
              KuboErp.Repo.query!("select set_config('app.tenant_id', $1, false)", [tenant_id])

              try do
                apply(__MODULE__, action_name(conn), [conn, conn.params])
              after
                KuboErp.Repo.query!("select set_config('app.tenant_id', '', false)")
              end
            end)
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
