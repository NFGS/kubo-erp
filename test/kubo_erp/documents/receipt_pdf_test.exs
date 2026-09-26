defmodule KuboErp.Documents.ReceiptPdfTest do
  @moduledoc """
  Comprobante en PDF (P-25). Sin base de datos: valida que el PDF escrito a mano
  sea **valido** —cabecera, tabla `xref` con desplazamientos reales y fin de
  archivo— y que el ticket traiga los datos de la venta.
  """

  use ExUnit.Case, async: true

  alias KuboErp.Documents.ReceiptPdf
  alias KuboErp.Sales.{Sale, SaleItem}

  setup_all do
    # La aplicacion configura tzdata al arrancar; estas pruebas puras no la
    # arrancan, y el comprobante necesita la zona del negocio. No basta con
    # registrar la base: tzdata debe estar iniciada para tener sus tablas.
    {:ok, _} = Application.ensure_all_started(:tzdata)
    Calendar.put_time_zone_database(Tzdata.TimeZoneDatabase)
    :ok
  end

  setup do
    venta = %Sale{
      id: Ecto.UUID.generate(),
      tenant_id: Ecto.UUID.generate(),
      number: "V-000123",
      customer_name: "Jose Ramirez",
      payment_method: "CASH",
      status: "COMPLETED",
      subtotal: Decimal.new("10000.00"),
      tax: Decimal.new("1900.00"),
      total: Decimal.new("11900.00"),
      table_number: "Mesa 4",
      inserted_at: ~N[2026-09-24 15:30:00],
      items: [
        %SaleItem{
          product_name: "Café molido",
          quantity: 2,
          unit_price: Decimal.new("5950.00"),
          tax_amount: Decimal.new("1900.00"),
          total: Decimal.new("11900.00")
        }
      ]
    }

    %{venta: venta}
  end

  test "el PDF es valido: cabecera, xref con desplazamientos reales y EOF", %{venta: venta} do
    {:ok, pdf} = ReceiptPdf.render(venta, tenant_name: "Tienda La Esquina")

    assert String.starts_with?(pdf, "%PDF-1.4")
    assert String.ends_with?(pdf, "%%EOF\n")

    # Cada desplazamiento del xref debe apuntar al objeto que declara.
    offsets =
      ~r/^(\d{10}) 00000 n $/m
      |> Regex.scan(pdf)
      |> Enum.map(fn [_, offset] -> String.to_integer(offset) end)

    assert length(offsets) == 5

    offsets
    |> Enum.with_index(1)
    |> Enum.each(fn {offset, numero} ->
      assert binary_part(pdf, offset, byte_size("#{numero} 0 obj")) == "#{numero} 0 obj"
    end)
  end

  test "el ticket trae los datos de la venta", %{venta: venta} do
    {:ok, pdf} = ReceiptPdf.render(venta, tenant_name: "Tienda La Esquina")

    assert pdf =~ "Tienda La Esquina"
    assert pdf =~ "V-000123"
    assert pdf =~ "Jose Ramirez"
    assert pdf =~ "Mesa 4"
    assert pdf =~ "11900.00"
    assert pdf =~ "Gracias por su compra"
  end

  test "los acentos viajan en WinAnsi (Latin-1)", %{venta: venta} do
    {:ok, pdf} = ReceiptPdf.render(venta, tenant_name: "Tienda La Esquina")

    # "Café" en Latin-1 es 43 61 66 E9; en UTF-8 seria 43 61 66 C3 A9.
    assert pdf =~ <<0x43, 0x61, 0x66, 0xE9>>
    refute pdf =~ <<0x43, 0x61, 0x66, 0xC3, 0xA9>>
  end

  test "la fecha se muestra en la zona del negocio", %{venta: venta} do
    {:ok, pdf} = ReceiptPdf.render(venta, timezone: "America/Bogota")

    # 15:30 UTC son las 10:30 en Bogota.
    assert pdf =~ "2026-09-24 10:30"
  end
end
