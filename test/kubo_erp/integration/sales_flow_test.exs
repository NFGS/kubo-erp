defmodule KuboErp.Integration.SalesFlowTest do
  @moduledoc """
  Pruebas de integracion contra PostgreSQL real (P-08).

  Una prueba pura puede verificar la aritmetica del dinero; solo la base de
  datos real verifica la politica RLS, la numeracion atomica por negocio, la
  atomicidad de la bandeja de salida y el kardex.

  Se ejecutan como el rol de la aplicacion, **no** como superusuario: los
  superusuarios ignoran RLS incluso con `FORCE`, y la prueba de aislamiento
  dejaria de probar algo.
  """

  use KuboErp.DataCase, async: false

  alias KuboErp.{Catalog, Repo, Sales}

  setup do
    tenant = Ecto.UUID.generate()
    %{tenant: tenant, producto: crear_producto(tenant)}
  end

  test "sin contexto de negocio no hay filas (RLS)", %{tenant: tenant, producto: producto} do
    vender(tenant, producto, 1)

    assert contar("sales") == 0
    assert contar("sales", Ecto.UUID.generate()) == 0
    assert contar("sales", tenant) == 1
  end

  test "la numeracion es consecutiva y por negocio", %{tenant: tenant, producto: producto} do
    numeros = for _ <- 1..3, do: vender(tenant, producto, 1).number
    assert numeros == ["V-000001", "V-000002", "V-000003"]

    otro = Ecto.UUID.generate()
    assert vender(otro, crear_producto(otro), 1).number == "V-000001"
  end

  test "la venta y su evento son atomicos", %{tenant: tenant, producto: producto} do
    venta = vender(tenant, producto, 2)
    assert contar_eventos(venta.id) == 1

    # Stock insuficiente: no debe quedar venta, ni evento, ni movimiento.
    assert {:error, {:insufficient_stock, _producto}} = vender(tenant, producto, 99)
    assert contar("sales", tenant) == 1
    assert contar_eventos(venta.id) == 1
    assert contar("stock_movements", tenant) == 2
  end

  test "la zona horaria del negocio manda sobre el respaldo (ADR-0012)", %{tenant: tenant} do
    stats = como_tenant(tenant, fn -> Sales.stats(tenant, "America/Mexico_City") end)
    assert stats.timezone == "America/Mexico_City"

    respaldo = como_tenant(tenant, fn -> Sales.stats(tenant) end)
    assert respaldo.timezone == Sales.business_timezone()
  end

  test "el kardex registra el movimiento y la anulacion lo revierte", %{
    tenant: tenant,
    producto: producto
  } do
    venta = vender(tenant, producto, 3)

    assert stock(tenant, producto) == 7

    assert Enum.any?(
             movimientos(tenant, producto),
             &(&1.kind == "OUT" and &1.reference_type == "SALE" and &1.stock_after == 7)
           )

    {:ok, anulada} =
      como_tenant(tenant, fn -> Sales.void_sale(tenant, Ecto.UUID.generate(), venta.id) end)

    assert anulada.status == "VOIDED"
    assert stock(tenant, producto) == 10

    assert Enum.any?(
             movimientos(tenant, producto),
             &(&1.kind == "IN" and &1.reference_type == "VOID" and &1.stock_after == 10)
           )
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp crear_producto(tenant) do
    como_tenant(tenant, fn ->
      {:ok, producto} =
        Catalog.create_product(tenant, %{
          "sku" => "IT-#{String.slice(tenant, 0, 8)}",
          "name" => "Producto Integracion",
          "price" => "11900.00",
          "cost" => "7000.00",
          "min_stock" => 2
        })

      {:ok, _producto, _movimiento} =
        Catalog.move_stock(producto, 10, kind: "IN", reason: "Prueba")

      producto
    end)
  end

  defp vender(tenant, producto, cantidad) do
    resultado =
      como_tenant(tenant, fn ->
        Sales.create_sale(tenant, Ecto.UUID.generate(), %{
          "items" => [%{"product_id" => producto.id, "quantity" => cantidad}],
          "payment_method" => "CASH"
        })
      end)

    case resultado do
      {:ok, venta} -> venta
      {:error, razon} -> {:error, razon}
    end
  end

  defp stock(tenant, producto) do
    como_tenant(tenant, fn ->
      %{rows: [[valor]]} =
        Repo.query!("select stock from products where id = $1", [Ecto.UUID.dump!(producto.id)])

      valor
    end)
  end

  defp movimientos(tenant, producto) do
    como_tenant(tenant, fn ->
      %{rows: filas} =
        Repo.query!(
          "select kind, reference_type, quantity, stock_after from stock_movements " <>
            "where product_id = $1 order by inserted_at",
          [Ecto.UUID.dump!(producto.id)]
        )

      Enum.map(filas, fn [kind, reference_type, quantity, stock_after] ->
        %{
          kind: kind,
          reference_type: reference_type,
          quantity: quantity,
          stock_after: stock_after
        }
      end)
    end)
  end

  defp contar(tabla, tenant \\ nil) do
    como_tenant(tenant, fn ->
      %{rows: [[total]]} = Repo.query!("select count(*) from #{tabla}")
      total
    end)
  end

  defp contar_eventos(sale_id) do
    %{rows: [[total]]} =
      Repo.query!(
        "select count(*) from outbox_events where payload->'data'->>'sale_id' = $1",
        [sale_id]
      )

    total
  end

  # El interceptor de tenant fija `app.tenant_id` a nivel de sesion sobre la
  # conexion reservada de la peticion y la limpia al terminar; aqui se replica
  # ese contrato (con nil se limpia, como al salir de la peticion).
  defp como_tenant(tenant_id, fun) do
    Repo.query!("select set_config('app.tenant_id', $1, false)", [tenant_id || ""])

    try do
      fun.()
    after
      Repo.query!("select set_config('app.tenant_id', '', false)")
    end
  end
end
