# syntax=docker/dockerfile:1.7

# ---------- Etapa 1: dependencias y compilacion ----------
FROM elixir:1.17-slim AS build

RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends ca-certificates build-essential git \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod

COPY mix.exs ./
COPY config ./config
RUN mix local.hex --force \
 && mix local.rebar --force \
 && mix deps.get --only prod

COPY lib ./lib
COPY priv ./priv
RUN mix compile

# ---------- Etapa 2: ejecucion ----------
FROM elixir:1.17-slim AS runtime

RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends ca-certificates wget openssl libstdc++6 gosu \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod \
    MIX_HOME=/app/.mix \
    HEX_HOME=/app/.hex

# Hex y rebar en el MIX_HOME del proyecto: `mix ecto:migrate` los necesita en
# ejecucion y el servidor corre como usuario sin privilegios.
RUN mix local.hex --force && mix local.rebar --force

COPY --from=build /app /app
COPY bin/docker-entrypoint /app/bin/docker-entrypoint
RUN chmod +x /app/bin/docker-entrypoint \
 && addgroup --system --gid 1000 kubo \
 && adduser --system --uid 1000 --ingroup kubo kubo \
 && chown -R kubo:kubo /app

EXPOSE 8083

HEALTHCHECK --interval=15s --timeout=5s --start-period=45s --retries=5 \
  CMD wget -qO- http://localhost:8083/api/v1/health || exit 1

ENTRYPOINT ["/app/bin/docker-entrypoint"]
CMD ["mix", "phx.server"]
