import Config

# TLS termina en el proxy inverso del despliegue (nginx/Traefik) y el servicio
# habla HTTP dentro de la red privada de contenedores. Dejar `force_ssl` activo
# aqui provocaria redirecciones 307 en cada peticion del gateway, porque el
# proxy reenvia con Host interno y sin X-Forwarded-Proto.
config :kubo_erp, KuboErpWeb.Endpoint, force_ssl: false

# No se imprimen mensajes de depuracion en produccion
config :logger, level: :info

# La configuracion de produccion que depende del entorno (DATABASE_URL,
# SECRET_KEY_BASE, AMQP_URL, puerto) se resuelve en config/runtime.exs.
