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

  alias KuboErp.{Catalog, Invoices, Notifications, Repo, Sales, Transfers, Warehouses}
  alias KuboErp.Notifications.Notification

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

  test "el aviso se encola y el entregador lo marca enviado (P-19)", %{tenant: tenant} do
    {:ok, aviso} =
      como_tenant(tenant, fn ->
        Notifications.notify(tenant, "LOW_STOCK", "Stock bajo de prueba", "Quedan 2 unidades")
      end)

    assert aviso.status == "PENDING", "el aviso nace encolado: la venta no espera al canal"

    resumen = como_sistema(fn -> Notifications.deliver_pending(5) end)
    assert resumen.sent >= 1

    recargado = como_tenant(tenant, fn -> Repo.get!(Notification, aviso.id) end)
    assert recargado.status == "SENT"
    assert recargado.sent_at
  end

  test "la venta descuenta de la bodega elegida (P-22)", %{tenant: tenant, producto: producto} do
    destino = como_tenant(tenant, fn -> Warehouses.default(tenant) end)
    {:ok, norte} = como_tenant(tenant, fn -> Warehouses.create(tenant, %{"name" => "Bodega norte"}) end)

    # La mercancia se mueve a la bodega norte y alli se vende.
    {:ok, _transferencia} =
      como_tenant(tenant, fn ->
        Transfers.create(tenant, Ecto.UUID.generate(), %{
          "from_warehouse_id" => destino.id,
          "to_warehouse_id" => norte.id,
          "items" => [%{"product_id" => producto.id, "quantity" => 6}]
        })
      end)

    {:ok, _venta} =
      como_tenant(tenant, fn ->
        Sales.create_sale(tenant, Ecto.UUID.generate(), %{
          "items" => [%{"product_id" => producto.id, "quantity" => 2}],
          "payment_method" => "CASH",
          "warehouse_id" => norte.id
        })
      end)

    assert nivel(tenant, norte.id, producto) == 4
    assert nivel(tenant, destino.id, producto) == 4
    assert stock(tenant, producto) == 8

    # Una bodega que no es del negocio no despacha la venta.
    assert {:error, :warehouse_not_found} =
             como_tenant(tenant, fn ->
               Sales.create_sale(tenant, Ecto.UUID.generate(), %{
                 "items" => [%{"product_id" => producto.id, "quantity" => 1}],
                 "payment_method" => "CASH",
                 "warehouse_id" => Ecto.UUID.generate()
               })
             end)
  end

  test "la transferencia mueve las dos bodegas y el total no cambia (P-22)", %{
    tenant: tenant,
    producto: producto
  } do
    origen = como_tenant(tenant, fn -> Warehouses.default(tenant) end)
    {:ok, destino} = como_tenant(tenant, fn -> Warehouses.create(tenant, %{"name" => "Bodega norte"}) end)

    {:ok, transferencia} =
      como_tenant(tenant, fn ->
        Transfers.create(tenant, Ecto.UUID.generate(), %{
          "from_warehouse_id" => origen.id,
          "to_warehouse_id" => destino.id,
          "items" => [%{"product_id" => producto.id, "quantity" => 4}]
        })
      end)

    # El total del producto no cambia: la mercancia sigue en el negocio.
    assert stock(tenant, producto) == 10
    assert nivel(tenant, origen.id, producto) == 6
    assert nivel(tenant, destino.id, producto) == 4

    # Kardex: dos movimientos con la misma referencia, uno por bodega.
    %{rows: filas} =
      como_tenant(tenant, fn ->
        Repo.query!(
          "select kind, warehouse_id from stock_movements where reference_type = 'TRANSFER' and reference_id = $1 order by kind",
          [Ecto.UUID.dump!(transferencia.id)]
        )
      end)

    assert filas == [["IN", Ecto.UUID.dump!(destino.id)], ["OUT", Ecto.UUID.dump!(origen.id)]]

    # Sin existencia en el origen no se mueve nada.
    assert {:error, {:insufficient_stock, _}} =
             como_tenant(tenant, fn ->
               Transfers.create(tenant, Ecto.UUID.generate(), %{
                 "from_warehouse_id" => origen.id,
                 "to_warehouse_id" => destino.id,
                 "items" => [%{"product_id" => producto.id, "quantity" => 99}]
               })
             end)

    assert nivel(tenant, origen.id, producto) == 6
    assert nivel(tenant, destino.id, producto) == 4
  end

  test "la factura se emite una sola vez y queda aislada por negocio (P-18)", %{
    tenant: tenant,
    producto: producto
  } do
    venta = vender(tenant, producto, 1)
    negocio = %{id: tenant, name: "Tienda Integracion"}

    {:ok, factura} = como_tenant(tenant, fn -> Invoices.issue(tenant, venta.id, negocio) end)
    assert String.match?(factura.cufe, ~r/^[0-9a-f]{96}$/)
    assert factura.xml =~ "<cbc:UBLVersionID>UBL 2.1</cbc:UBLVersionID>"

    # La factura deja su XML como documento, con el hash de su contenido.
    documento =
      como_tenant(tenant, fn ->
        KuboErp.Documents.list(tenant, 1) |> List.first()
      end)

    assert documento.kind == "INVOICE_XML"
    assert documento.content_type == "application/xml"
    assert documento.reference_id == factura.id

    {:ok, contenido} = como_tenant(tenant, fn -> KuboErp.Documents.content(documento) end)
    assert :crypto.hash(:sha256, contenido) |> Base.encode16(case: :lower) == documento.sha256

    {:ok, repetida} = como_tenant(tenant, fn -> Invoices.issue(tenant, venta.id, negocio) end)
    assert repetida.id == factura.id, "emitir dos veces devuelve la misma factura"

    # RLS: otro negocio no ve la factura.
    otro = Ecto.UUID.generate()
    assert como_tenant(otro, fn -> Invoices.get_by_sale(otro, venta.id) end) == nil
  end

  test "una venta anulada no se factura (P-18)", %{tenant: tenant, producto: producto} do
    venta = vender(tenant, producto, 1)

    {:ok, _anulada} =
      como_tenant(tenant, fn -> Sales.void_sale(tenant, Ecto.UUID.generate(), venta.id) end)

    assert {:error, :sale_voided} =
             como_tenant(tenant, fn ->
               Invoices.issue(tenant, venta.id, %{id: tenant, name: "Tienda"})
             end)
  end

  test "el paquete siembra un catalogo de arranque idempotente (P-17)", %{tenant: tenant} do
    pack = KuboErp.Packs.get("restaurantes")

    primera = como_tenant(tenant, fn -> Catalog.seed_pack(tenant, pack) end)
    assert primera.created == 3
    assert primera.skipped == 0

    segunda = como_tenant(tenant, fn -> Catalog.seed_pack(tenant, pack) end)
    assert segunda.created == 0
    assert segunda.skipped == 3

    # Los productos nacen con el inventario del vertical (restaurantes si lleva).
    %{rows: filas} =
      como_tenant(tenant, fn ->
        Repo.query!("select sku, tracks_stock from products where sku like 'PLT-%' order by sku")
      end)

    assert filas == [["PLT-001", true], ["PLT-002", true], ["PLT-003", true]]
  end

  test "un servicio no mueve kardex y la venta guarda la mesa (P-17)", %{tenant: tenant} do
    servicio =
      como_tenant(tenant, fn ->
        {:ok, producto} =
          Catalog.create_product(tenant, %{
            "sku" => "SRV-#{String.slice(tenant, 0, 8)}",
            "name" => "Corte de cabello",
            "price" => "30000.00",
            "cost" => "0",
            "tracks_stock" => false
          })

        producto
      end)

    venta =
      como_tenant(tenant, fn ->
        Sales.create_sale(tenant, Ecto.UUID.generate(), %{
          "items" => [%{"product_id" => servicio.id, "quantity" => 5}],
          "payment_method" => "CASH",
          "table_number" => "Mesa 4"
        })
      end)

    assert {:ok, %{table_number: "Mesa 4"} = vendida} = venta
    assert vendida.total == Decimal.new("150000.00")

    # Sin stock ni kardex: el servicio no lleva inventario.
    assert stock(tenant, servicio) == 0
    assert movimientos(tenant, servicio) == []
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

  # El entregador es un proceso de sistema: barre pendientes de todos los
  # negocios con la marca `app.system` (ADR-0017).
  defp como_sistema(fun) do
    Repo.query!("select set_config('app.system', 'on', false)")

    try do
      {:ok, resultado} = Repo.transaction(fn -> fun.() end)
      resultado
    after
      Repo.query!("select set_config('app.system', 'off', false)")
    end
  end

  defp nivel(tenant, warehouse_id, producto) do
    como_tenant(tenant, fn ->
      %{rows: [[valor]]} =
        Repo.query!(
          "select stock from stock_levels where warehouse_id = $1 and product_id = $2",
          [Ecto.UUID.dump!(warehouse_id), Ecto.UUID.dump!(producto.id)]
        )

      valor
    end)
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
