defmodule KuboErp.MixProject do
  use Mix.Project

  def project do
    [
      app: :kubo_erp,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      # Cobertura: la capa web y los flujos completos los cubre el humo (184
      # comprobaciones contra el sistema vivo); este gate es un ratchet de la
      # suite ExUnit para que la cobertura no baje del valor actual.
      test_coverage: [summary: [threshold: 35]]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {KuboErp.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.14"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:amqp, "~> 4.2"},
      {:bandit, "~> 1.5"},
      # Correo real de las notificaciones (P-19): Swoosh + gen_smtp.
      {:swoosh, "~> 1.16"},
      {:gen_smtp, "~> 1.2"},
      # Cliente HTTP que Swoosh arranca aunque el envio sea por SMTP.
      {:hackney, "~> 1.20"},
      # Base de datos de zonas horarias: sin ella `DateTime.now("America/Bogota")`
      # devuelve error y el dia comercial caeria a UTC (bug A-01).
      {:tzdata, "~> 1.1"},
      # Trazas OpenTelemetry (P-07): SDK, exportador OTLP e instrumentacion de
      # Phoenix y Ecto.
      {:opentelemetry, "~> 1.5"},
      {:opentelemetry_api, "~> 1.4"},
      {:opentelemetry_exporter, "~> 1.8"},
      {:opentelemetry_phoenix, "~> 2.0"},
      {:opentelemetry_ecto, "~> 1.2"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
