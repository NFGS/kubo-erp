defmodule KuboErp.InternalUsage do
  @moduledoc """
  Uso agregado por negocio para el panel de plataforma (ADR-0025).

  El panel del operador ve **conteos**, nunca datos de negocio. Como el ERP no
  conoce la lista de negocios (esa vive en IAM), el endpoint recibe los
  identificadores y consulta cada negocio **con su propia marca de aislamiento**
  (`app.tenant_id`): no se amplía la política RLS ni se cruzan negocios.

  Solo lo alcanza la malla interna (mTLS): no hay ruta pública hacia aqui.
  """

  import Ecto.Query

  alias KuboErp.Documents.Document
  alias KuboErp.Catalog.Product
  alias KuboErp.Repo
  alias KuboErp.Sales.Sale
  alias KuboErp.Warehouses.Warehouse

  @doc """
  Devuelve, por negocio, los conteos del plan: productos, bodegas, ventas del
  mes (UTC, para la métrica del operador) y documentos con su tamaño.
  """
  def for_tenants(tenant_ids) when is_list(tenant_ids) do
    Enum.map(tenant_ids, &for_tenant/1)
  end

  def for_tenant(tenant_id) do
    Repo.checkout(fn ->
      Repo.query!("select set_config('app.tenant_id', $1, false)", [tenant_id])

      try do
        %{
          tenant_id: tenant_id,
          products: cuenta(Product),
          warehouses: cuenta(Warehouse),
          sales_month: ventas_del_mes(),
          documents: documentos()
        }
      after
        Repo.query!("select set_config('app.tenant_id', '', false)")
      end
    end)
  end

  defp cuenta(modulo), do: Repo.aggregate(modulo, :count, :id)

  defp ventas_del_mes do
    # El mes en UTC: es una metrica del operador (conteos), no un numero de
    # negocio, asi que no necesita la zona horaria de cada negocio.
    desde =
      Date.utc_today()
      |> Date.beginning_of_month()
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    consulta =
      from(s in Sale,
        where: s.status == "COMPLETED" and s.inserted_at >= ^desde,
        select: %{count: count(s.id), revenue: coalesce(sum(s.total), 0)}
      )

    %{count: cuenta, revenue: revenue} = Repo.one(consulta)

    %{count: cuenta, revenue: Decimal.to_string(revenue)}
  end

  defp documentos do
    consulta =
      from(d in Document,
        select: %{count: count(d.id), bytes: coalesce(sum(d.size), 0)}
      )

    %{count: cuenta, bytes: bytes} = Repo.one(consulta)

    %{count: cuenta, bytes: bytes}
  end
end
