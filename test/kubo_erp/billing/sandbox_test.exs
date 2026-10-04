defmodule KuboErp.Billing.SandboxTest do
  @moduledoc """
  Adaptador de facturacion sandbox (P-18). No requiere base de datos: valida el
  CUFE, la estructura UBL 2.1 y el escapado de los datos del negocio y del
  cliente.
  """

  use ExUnit.Case, async: true

  alias KuboErp.Billing.Sandbox
  alias KuboErp.Sales.{Sale, SaleItem}

  setup do
    venta = %Sale{
      id: Ecto.UUID.generate(),
      tenant_id: Ecto.UUID.generate(),
      number: "V-000042",
      customer_name: "Cliente & Cia <prueba>",
      payment_method: "CASH",
      status: "COMPLETED",
      subtotal: Decimal.new("10000.00"),
      tax: Decimal.new("1900.00"),
      total: Decimal.new("11900.00"),
      items: [
        %SaleItem{
          product_name: "Cafe molido",
          quantity: 2,
          unit_price: Decimal.new("5950.00"),
          tax_amount: Decimal.new("1900.00"),
          total: Decimal.new("11900.00")
        }
      ]
    }

    %{
      venta: venta,
      tenant: %{
        id: "negocio-1",
        name: "Tienda & Cia",
        tax_id: "900123456",
        tax_id_dv: "8",
        fiscal_address: "Calle 1 # 2-3",
        tax_regime: "RESPONSABLE_IVA",
        invoice_prefix: "FE"
      }
    }
  end

  test "el CUFE es hexadecimal de 96 caracteres y sigue a la venta", %{
    venta: venta,
    tenant: tenant
  } do
    {:ok, factura} = Sandbox.issue(tenant, venta)

    assert String.match?(factura.cufe, ~r/^[0-9a-f]{96}$/)
    assert factura.number == "FE-000042"
    assert factura.status == "ISSUED"
    assert factura.qr_url =~ factura.cufe
  end

  test "el prefijo de facturacion lo define el negocio", %{venta: venta, tenant: tenant} do
    {:ok, factura} = Sandbox.issue(%{tenant | invoice_prefix: "FV"}, venta)

    assert factura.number == "FV-000042"
  end

  test "el CUFE cambia con los datos y es estable con los mismos", %{venta: venta, tenant: tenant} do
    {:ok, primera} = Sandbox.issue(tenant, venta)
    {:ok, otra_venta} = Sandbox.issue(tenant, %{venta | total: Decimal.new("99999.00")})

    assert primera.cufe != otra_venta.cufe
  end

  test "el XML es UBL 2.1, trae los totales y escapa los datos", %{venta: venta, tenant: tenant} do
    {:ok, factura} = Sandbox.issue(tenant, venta)
    xml = factura.xml

    assert xml =~ "<cbc:UBLVersionID>UBL 2.1</cbc:UBLVersionID>"
    assert xml =~ "<cbc:ID>FE-000042</cbc:ID>"
    assert xml =~ "<cbc:UUID schemeName=\"CUFE-SHA384\">#{factura.cufe}</cbc:UUID>"
    assert xml =~ ~s(<cbc:PayableAmount currencyID="COP">11900.00</cbc:PayableAmount>)
    assert xml =~ "Cliente &amp; Cia &lt;prueba&gt;"
    assert xml =~ "Tienda &amp; Cia"
    assert xml =~ ~s(<cbc:CompanyID schemeName="31" schemeID="8">900123456</cbc:CompanyID>)
    assert xml =~ "<cbc:TaxLevelCode>RESPONSABLE_IVA</cbc:TaxLevelCode>"
    assert xml =~ "<cbc:StreetName>Calle 1 # 2-3</cbc:StreetName>"
    assert xml =~ "Cafe molido"
  end

  test "la nota credito referencia la factura, con CUDE propio y tipo 91", %{
    venta: venta,
    tenant: tenant
  } do
    {:ok, factura} = Sandbox.issue(tenant, venta)
    {:ok, nota} = Sandbox.issue_credit_note(tenant, venta, factura, "Anulacion de la venta V-000042")

    assert String.match?(nota.cude, ~r/^[0-9a-f]{96}$/)
    assert nota.cude != factura.cufe
    assert nota.number == "NC-000042"
    assert nota.qr_url =~ nota.cude

    assert nota.xml =~ "<CreditNote"
    assert nota.xml =~ "<cbc:CreditNoteTypeCode>91</cbc:CreditNoteTypeCode>"
    assert nota.xml =~ "<cbc:ID>NC-000042</cbc:ID>"
    assert nota.xml =~ "<cbc:UUID schemeName=\"CUDE-SHA384\">#{nota.cude}</cbc:UUID>"
    # Referencia a la factura que corrige: sin ella la nota no corrige nada.
    assert nota.xml =~ "<cbc:ReferenceID>FE-000042</cbc:ReferenceID>"
    assert nota.xml =~ "<cbc:UUID schemeName=\"CUFE-SHA384\">#{factura.cufe}</cbc:UUID>"
    assert nota.xml =~ "Anulacion de la venta V-000042"
    assert nota.xml =~ "Cafe molido"
  end

  test "sin NIT registrado se usa el marcador documentado", %{venta: venta} do
    {:ok, factura} = Sandbox.issue(%{id: "negocio-1", name: "Tienda"}, venta)

    assert factura.xml =~ ~s(<cbc:CompanyID schemeName="31">900000000</cbc:CompanyID>)
  end
end
