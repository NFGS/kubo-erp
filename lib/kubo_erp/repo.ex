defmodule KuboErp.Repo do
  use Ecto.Repo,
    otp_app: :kubo_erp,
    adapter: Ecto.Adapters.Postgres
end
