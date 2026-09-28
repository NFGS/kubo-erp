defmodule KuboErpWeb.UsageController do
  @moduledoc """
  Uso del negocio para su plan (F6.1, ADR-0021).

  El operador necesita saber cuanto consume cada negocio y el negocio necesita
  verlo contra su plan; los cupos que no viven aqui (usuarios) los aporta IAM.
  """

  use KuboErpWeb, :controller

  alias KuboErp.{Catalog, Documents, Sales, Warehouses}

  def show(conn, _params) do
    tenant_id = conn.assigns.tenant_id
    timezone = conn.assigns[:tenant_timezone]

    ventas = Sales.monthly_usage(tenant_id, timezone)
    documentos = Documents.usage(tenant_id)

    json(conn, %{
      data: %{
        warehouses: length(Warehouses.list(tenant_id)),
        products: Catalog.count_products(tenant_id),
        sales_month: %{month: ventas.month, count: ventas.count, revenue: ventas.revenue},
        documents: documentos
      }
    })
  end
end
