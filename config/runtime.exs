import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/kubo_erp start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :kubo_erp, KuboErpWeb.Endpoint, server: true
end

config :kubo_erp, KuboErpWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Bus de eventos. Si la variable esta vacia, el servicio opera sin publicar
# eventos (degradacion elegante: la venta nunca falla por la mensajeria).
config :kubo_erp, :amqp_url, System.get_env("AMQP_URL")

# Zona horaria del negocio. Se usa para responder "¿que se vendio hoy?" con el
# dia comercial real y no con el dia UTC: en Colombia (UTC-5) las ventas
# posteriores a las 19:00 pertenecen al dia anterior en UTC.
config :kubo_erp, :timezone, System.get_env("KUBO_TIMEZONE", "America/Bogota")

# Trazas OTLP hacia el collector (P-07). Sin endpoint configurado, la
# aplicacion arranca sin exportar: la observabilidad nunca es un requisito para
# vender.
if otlp_endpoint = System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") do
  config :opentelemetry,
    resource: %{service: %{name: "kubo-erp"}},
    traces_exporter: :otlp

  config :opentelemetry_exporter,
    otlp_protocol: :http_protobuf,
    otlp_endpoint: otlp_endpoint
end

# Documentos (P-25, ADR-0018): raiz del almacenamiento en disco. Se lee en todos
# los entornos —las pruebas usan una carpeta temporal— y en produccion debe ser
# un volumen: entra en el respaldo junto con la base.
config :kubo_erp, :documents_path, System.get_env("KUBO_DOCUMENTS_PATH", "priv/documents")

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :kubo_erp, KuboErp.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :kubo_erp, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :kubo_erp, KuboErpWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # Notificaciones (P-19, ADR-0017): canal y correo real. La misma familia de
  # variables que usa IAM (KUBO_SMTP_*), de modo que un despliegue configura el
  # correo una sola vez para todo el sistema. El valor se calcula antes de
  # `config` para no dejar un `case` como argumento de la macro.
  notifications_adapter =
    case System.get_env("KUBO_NOTIFICATIONS_ADAPTER") do
      "smtp" -> KuboErp.Notifications.Smtp
      "whatsapp" -> KuboErp.Notifications.Whatsapp
      _ -> KuboErp.Notifications.Log
    end

  config :kubo_erp, KuboErp.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: System.get_env("KUBO_SMTP_HOST"),
    port: String.to_integer(System.get_env("KUBO_SMTP_PORT", "587")),
    username: System.get_env("KUBO_SMTP_USERNAME"),
    password: System.get_env("KUBO_SMTP_PASSWORD"),
    tls: :if_available,
    auth: :always,
    no_mx_lookups: true

  config :kubo_erp, :smtp,
    host: System.get_env("KUBO_SMTP_HOST"),
    from: System.get_env("KUBO_SMTP_FROM", "no-responder@kubo.local"),
    recipient: System.get_env("KUBO_NOTIFICATIONS_EMAIL")

  config :kubo_erp, :notifications_adapter, notifications_adapter

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :kubo_erp, KuboErpWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :kubo_erp, KuboErpWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
