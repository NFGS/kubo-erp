defmodule KuboErp.Integration.NotificationsTest do
  @moduledoc """
  Notificaciones (P-19, ADR-0017) contra PostgreSQL real: la cola de entrega, el
  aviso de compra y el resumen diario idempotente.
  """

  use KuboErp.DataCase, async: false

  import Ecto.Query

  alias KuboErp.{Catalog, Notifications, Purchases, Repo, Sales, Suppliers}
  alias KuboErp.Notifications.{Notification, Summarizer}

  setup do
    tenant = Ecto.UUID.generate()
    %{tenant: tenant, producto: crear_producto(tenant)}
  end

  test "la compra recibida deja su aviso encolado (P-19)", %{tenant: tenant, producto: producto} do
    {:ok, proveedor} =
      como_tenant(tenant, fn -> Suppliers.create(tenant, %{"name" => "Proveedor Prueba"}) end)

    {:ok, _compra} =
      como_tenant(tenant, fn ->
        Purchases.create(tenant, Ecto.UUID.generate(), %{
          "supplier_id" => proveedor.id,
          "items" => [%{"product_id" => producto.id, "quantity" => 4, "unit_cost" => "1000.00"}]
        })
      end)

    avisos = como_tenant(tenant, fn -> Notifications.list(tenant) end)
    compra = Enum.find(avisos, &(&1.kind == "PURCHASE"))

    assert compra
    assert compra.status == "PENDING"
    assert compra.subject =~ "recibida"
  end

  test "el resumen diario se encola una sola vez por dia (P-19)", %{
    tenant: tenant,
    producto: producto
  } do
    vender(tenant, producto, 1)

    Summarizer.resumir_negocios()
    Summarizer.resumir_negocios()

    resumenes =
      como_sistema(fn ->
        Repo.all(
          from(n in Notification, where: n.tenant_id == ^tenant and n.kind == "DAILY_SUMMARY")
        )
      end)

    assert length(resumenes) == 1, "el resumen es idempotente: no se repite el mismo dia"
    assert hd(resumenes).subject =~ "Resumen del dia"
  end

  # --- helpers ---------------------------------------------------------------

  defp crear_producto(tenant) do
    como_tenant(tenant, fn ->
      {:ok, producto} =
        Catalog.create_product(tenant, %{
          "sku" => "NT-#{String.slice(tenant, 0, 8)}",
          "name" => "Producto Notificaciones",
          "price" => "11900.00",
          "cost" => "7000.00"
        })

      {:ok, _producto, _movimiento} =
        Catalog.move_stock(producto, 10, kind: "IN", reason: "Prueba")

      producto
    end)
  end

  defp vender(tenant, producto, cantidad) do
    {:ok, venta} =
      como_tenant(tenant, fn ->
        Sales.create_sale(tenant, Ecto.UUID.generate(), %{
          "items" => [%{"product_id" => producto.id, "quantity" => cantidad}],
          "payment_method" => "CASH"
        })
      end)

    venta
  end

  defp como_tenant(tenant_id, fun) do
    Repo.query!("select set_config('app.tenant_id', $1, false)", [tenant_id || ""])

    try do
      fun.()
    after
      Repo.query!("select set_config('app.tenant_id', '', false)")
    end
  end

  defp como_sistema(fun) do
    Repo.query!("select set_config('app.system', 'on', false)")

    try do
      {:ok, resultado} = Repo.transaction(fn -> fun.() end)
      resultado
    after
      Repo.query!("select set_config('app.system', 'off', false)")
    end
  end
end
