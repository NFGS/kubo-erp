defmodule KuboErp.Repo do
  use Ecto.Repo,
    otp_app: :kubo_erp,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Transaccion de negocio que respeta la transaccion externa del interceptor de
  tenant (P-02).

  El interceptor envuelve cada accion en una transaccion con `app.tenant_id`.
  Dentro de ella, las operaciones de negocio (venta, anulacion, ajuste de
  stock) abren su propia transaccion: si se anidara sin savepoint, un
  `Repo.rollback` de negocio —por ejemplo, stock insuficiente— abortaria la
  transaccion completa y tumbaria la peticion despues de haber respondido.

  Con `mode: :savepoint` el rollback de negocio deshace solo su parte y la
  transaccion externa puede confirmar el resto (tipicamente, nada mas).
  Fuera de una transaccion se comporta como una transaccion normal.
  """
  def scoped_transaction(fun) when is_function(fun, 0) do
    if in_transaction?() do
      transaction(fun, mode: :savepoint)
    else
      transaction(fun)
    end
  end
end
