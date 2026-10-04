defmodule KuboErp.Billing.Sandbox do
  @moduledoc """
  Adaptador de facturacion para desarrollo y habilitacion (ADR-0014).

  Genera un documento con la estructura UBL 2.1 que pide la DIAN, el CUFE
  calculado con su algoritmo (SHA-384 de la cadena de datos) y el enlace del QR
  del catalogo. **No sustituye al proveedor tecnologico**: el XML no se envia a
  la DIAN ni tiene validez fiscal. Un proveedor real implementa el mismo
  contrato (`KuboErp.Billing`).

  El NIT del negocio y la clave tecnica son marcadores: la habilitacion exige
  registrarlos ante la DIAN (tramite externo, ver el plan de cierre).
  """

  @behaviour KuboErp.Billing

  alias KuboErp.Sales.Sale

  @nit_marcador "900000000"
  @clave_tecnica "kubo-sandbox-clave-tecnica"
  @documento_consumidor_final "222222222222"

  @impl true
  def issue(tenant, %Sale{} = sale) do
    issued_at = DateTime.utc_now() |> DateTime.truncate(:second)
    number = invoice_number(tenant, sale)
    cufe = cufe(tenant, sale, number, issued_at)
    qr_url = "https://catalogo-vpfe.dian.gov.co/document/searchqr?documentkey=#{cufe}"
    xml = ubl(tenant, sale, number, cufe, issued_at)

    {:ok, %{number: number, cufe: cufe, qr_url: qr_url, xml: xml, status: "ISSUED"}}
  end

  @impl true
  def issue_credit_note(tenant, %Sale{} = sale, invoice, reason) do
    issued_at = DateTime.utc_now() |> DateTime.truncate(:second)
    number = credit_note_number(sale)
    cude = cude(tenant, sale, invoice, number, issued_at)
    qr_url = "https://catalogo-vpfe.dian.gov.co/document/searchqr?documentkey=#{cude}"
    xml = ubl_credit_note(tenant, sale, invoice, number, cude, reason, issued_at)

    {:ok, %{number: number, cude: cude, qr_url: qr_url, xml: xml, status: "ISSUED"}}
  end

  # La numeracion de la factura sigue a la de la venta: un negocio de barrio
  # identifica ambas con el mismo consecutivo. El prefijo lo define el negocio
  # (resolucion de facturacion); "FE" es el respaldo.
  defp invoice_number(tenant, %Sale{number: "V-" <> consecutivo}), do: "#{prefijo(tenant)}-" <> consecutivo
  defp credit_note_number(%Sale{number: "V-" <> consecutivo}), do: "NC-" <> consecutivo

  defp prefijo(%{invoice_prefix: prefijo}) when is_binary(prefijo) and prefijo != "", do: prefijo
  defp prefijo(_tenant), do: "FE"

  @doc """
  CUDE segun la DIAN: SHA-384 de la concatenacion de los datos de la nota y el
  CUFE de la factura que corrige (NumNC + FecNC + HorNC + ValNC + ... +
  NumFac + CUFE + NitOFE + NumAdq + ClTec + TipoAmbiente), en hexadecimal.
  """
  def cude(tenant, %Sale{} = sale, invoice, number, issued_at) do
    cadena =
      [
        number,
        Calendar.strftime(issued_at, "%Y-%m-%d"),
        Calendar.strftime(issued_at, "%H:%M:%S%z"),
        dinero(sale.total),
        "01",
        dinero(sale.tax),
        invoice.number,
        invoice.cufe,
        nit(tenant),
        @documento_consumidor_final,
        @clave_tecnica,
        environment()
      ]
      |> Enum.join("")

    :sha384
    |> :crypto.hash(cadena)
    |> Base.encode16(case: :lower)
  end

  @doc """
  CUFE segun la DIAN: SHA-384 de la concatenacion de
  NumFac + FecFac + HorFac + ValFac + CodImp1 + ValImp1 + ... + ValTot +
  NitOFE + NumAdq + ClTec + TipoAmbiente, en hexadecimal.
  """
  def cufe(tenant, %Sale{} = sale, number, issued_at) do
    cadena =
      [
        number,
        Calendar.strftime(issued_at, "%Y-%m-%d"),
        Calendar.strftime(issued_at, "%H:%M:%S%z"),
        dinero(sale.subtotal),
        "01",
        dinero(sale.tax),
        "04",
        "0.00",
        "03",
        "0.00",
        dinero(sale.total),
        nit(tenant),
        @documento_consumidor_final,
        @clave_tecnica,
        environment()
      ]
      |> Enum.join("")

    :sha384
    |> :crypto.hash(cadena)
    |> Base.encode16(case: :lower)
  end

  @doc "Ambiente DIAN: 1 produccion, 2 habilitacion. Lo define la configuracion."
  def environment, do: KuboErp.Billing.environment()

  defp nit(%{tax_id: nit}) when is_binary(nit) and nit != "", do: nit
  defp nit(_tenant), do: @nit_marcador

  defp dv(%{tax_id_dv: dv}) when is_binary(dv) and dv != "", do: dv
  defp dv(_tenant), do: nil

  # CompanyID con el digito de verificacion (schemeName 31 = NIT).
  defp company_id(tenant) do
    case dv(tenant) do
      nil -> "<cbc:CompanyID schemeName=\"31\">#{esc(nit(tenant))}</cbc:CompanyID>"
      dv -> "<cbc:CompanyID schemeName=\"31\" schemeID=\"#{esc(dv)}\">#{esc(nit(tenant))}</cbc:CompanyID>"
    end
  end

  # Regimen y direccion fiscal: el proveedor tecnologico los mapea a los codigos
  # oficiales de la DIAN; el sandbox los deja legibles para la habilitacion.
  defp parte_fiscal(tenant) do
    [regimen(tenant), direccion(tenant)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n          ")
  end

  defp regimen(%{tax_regime: regimen}) when is_binary(regimen) and regimen != "" do
    "<cbc:TaxLevelCode>#{esc(regimen)}</cbc:TaxLevelCode>"
  end

  defp regimen(_tenant), do: ""

  defp direccion(%{fiscal_address: direccion}) when is_binary(direccion) and direccion != "" do
    "<cac:RegistrationAddress><cbc:StreetName>#{esc(direccion)}</cbc:StreetName></cac:RegistrationAddress>"
  end

  defp direccion(_tenant), do: ""

  defp dinero(%Decimal{} = valor), do: Decimal.to_string(valor, :normal)
  defp dinero(valor), do: to_string(valor)

  # ---------------------------------------------------------------------------
  # UBL 2.1
  # ---------------------------------------------------------------------------

  defp ubl_credit_note(tenant, sale, invoice, number, cude, reason, issued_at) do
    lineas =
      sale.items
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {item, indice} -> linea_credito(item, indice) end)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <CreditNote xmlns="urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2"
                xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
                xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
      <cbc:UBLVersionID>UBL 2.1</cbc:UBLVersionID>
      <cbc:ProfileID>DIAN 2.1</cbc:ProfileID>
      <cbc:ID>#{esc(number)}</cbc:ID>
      <cbc:UUID schemeName="CUDE-SHA384">#{esc(cude)}</cbc:UUID>
      <cbc:IssueDate>#{Calendar.strftime(issued_at, "%Y-%m-%d")}</cbc:IssueDate>
      <cbc:IssueTime>#{Calendar.strftime(issued_at, "%H:%M:%S%z")}</cbc:IssueTime>
      <cbc:CreditNoteTypeCode>91</cbc:CreditNoteTypeCode>
      <cbc:Note>#{esc(reason)}</cbc:Note>
      <cbc:DocumentCurrencyCode>COP</cbc:DocumentCurrencyCode>
      <cac:DiscrepancyResponse>
        <cbc:ReferenceID>#{esc(invoice.number)}</cbc:ReferenceID>
        <cbc:ResponseCode>2</cbc:ResponseCode>
        <cbc:Description>#{esc(reason)}</cbc:Description>
      </cac:DiscrepancyResponse>
      <cac:BillingReference>
        <cac:InvoiceDocumentReference>
          <cbc:ID>#{esc(invoice.number)}</cbc:ID>
          <cbc:UUID schemeName="CUFE-SHA384">#{esc(invoice.cufe)}</cbc:UUID>
        </cac:InvoiceDocumentReference>
      </cac:BillingReference>
      <cac:AccountingSupplierParty>
        <cac:Party>
          <cac:PartyName><cbc:Name>#{esc(nombre(tenant))}</cbc:Name></cac:PartyName>
          <cac:PartyTaxScheme>
            #{company_id(tenant)}
            <cac:TaxScheme><cbc:ID>01</cbc:ID><cbc:Name>IVA</cbc:Name></cac:TaxScheme>
          </cac:PartyTaxScheme>
          #{parte_fiscal(tenant)}
        </cac:Party>
      </cac:AccountingSupplierParty>
      <cac:AccountingCustomerParty>
        <cac:Party>
          <cac:PartyName><cbc:Name>#{esc(sale.customer_name || "Consumidor final")}</cbc:Name></cac:PartyName>
          <cac:PartyIdentification><cbc:ID>#{@documento_consumidor_final}</cbc:ID></cac:PartyIdentification>
        </cac:Party>
      </cac:AccountingCustomerParty>
      <cac:TaxTotal>
        <cbc:TaxAmount currencyID="COP">#{dinero(sale.tax)}</cbc:TaxAmount>
      </cac:TaxTotal>
      <cac:LegalMonetaryTotal>
        <cbc:LineExtensionAmount currencyID="COP">#{dinero(sale.subtotal)}</cbc:LineExtensionAmount>
        <cbc:TaxExclusiveAmount currencyID="COP">#{dinero(sale.subtotal)}</cbc:TaxExclusiveAmount>
        <cbc:TaxInclusiveAmount currencyID="COP">#{dinero(sale.total)}</cbc:TaxInclusiveAmount>
        <cbc:PayableAmount currencyID="COP">#{dinero(sale.total)}</cbc:PayableAmount>
      </cac:LegalMonetaryTotal>
    #{lineas}
      <cac:AdditionalDocumentReference>
        <cbc:ID>QR</cbc:ID>
        <cac:Attachment>
          <cbc:ExternalReference>https://catalogo-vpfe.dian.gov.co/document/searchqr?documentkey=#{esc(cude)}</cbc:ExternalReference>
        </cac:Attachment>
      </cac:AdditionalDocumentReference>
    </CreditNote>
    """
  end

  defp linea_credito(item, indice) do
    bruto = Decimal.mult(item.unit_price, Decimal.new(item.quantity))

    """
      <cac:CreditNoteLine>
        <cbc:ID>#{indice}</cbc:ID>
        <cbc:CreditedQuantity unitCode="94">#{item.quantity}</cbc:CreditedQuantity>
        <cbc:LineExtensionAmount currencyID="COP">#{dinero(Decimal.sub(bruto, item.tax_amount))}</cbc:LineExtensionAmount>
        <cac:TaxTotal>
          <cbc:TaxAmount currencyID="COP">#{dinero(item.tax_amount)}</cbc:TaxAmount>
        </cac:TaxTotal>
        <cac:Item><cbc:Description>#{esc(item.product_name)}</cbc:Description></cac:Item>
        <cac:Price><cbc:PriceAmount currencyID="COP">#{dinero(item.unit_price)}</cbc:PriceAmount></cac:Price>
      </cac:CreditNoteLine>
    """
    |> String.trim_trailing()
  end

  defp ubl(tenant, sale, number, cufe, issued_at) do
    lineas =
      sale.items
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {item, indice} -> linea(item, indice) end)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
             xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
             xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
      <cbc:UBLVersionID>UBL 2.1</cbc:UBLVersionID>
      <cbc:ProfileID>DIAN 2.1</cbc:ProfileID>
      <cbc:ID>#{esc(number)}</cbc:ID>
      <cbc:UUID schemeName="CUFE-SHA384">#{esc(cufe)}</cbc:UUID>
      <cbc:IssueDate>#{Calendar.strftime(issued_at, "%Y-%m-%d")}</cbc:IssueDate>
      <cbc:IssueTime>#{Calendar.strftime(issued_at, "%H:%M:%S%z")}</cbc:IssueTime>
      <cbc:InvoiceTypeCode>01</cbc:InvoiceTypeCode>
      <cbc:DocumentCurrencyCode>COP</cbc:DocumentCurrencyCode>
      <cbc:LineCountNumeric>#{length(sale.items)}</cbc:LineCountNumeric>
      <cac:AccountingSupplierParty>
        <cac:Party>
          <cac:PartyName><cbc:Name>#{esc(nombre(tenant))}</cbc:Name></cac:PartyName>
          <cac:PartyTaxScheme>
            #{company_id(tenant)}
            <cac:TaxScheme><cbc:ID>01</cbc:ID><cbc:Name>IVA</cbc:Name></cac:TaxScheme>
          </cac:PartyTaxScheme>
          #{parte_fiscal(tenant)}
        </cac:Party>
      </cac:AccountingSupplierParty>
      <cac:AccountingCustomerParty>
        <cac:Party>
          <cac:PartyName><cbc:Name>#{esc(sale.customer_name || "Consumidor final")}</cbc:Name></cac:PartyName>
          <cac:PartyIdentification><cbc:ID>#{@documento_consumidor_final}</cbc:ID></cac:PartyIdentification>
        </cac:Party>
      </cac:AccountingCustomerParty>
      <cac:TaxTotal>
        <cbc:TaxAmount currencyID="COP">#{dinero(sale.tax)}</cbc:TaxAmount>
        <cac:TaxSubtotal>
          <cbc:TaxableAmount currencyID="COP">#{dinero(sale.subtotal)}</cbc:TaxableAmount>
          <cbc:TaxAmount currencyID="COP">#{dinero(sale.tax)}</cbc:TaxAmount>
          <cac:TaxCategory>
            <cac:TaxScheme><cbc:ID>01</cbc:ID><cbc:Name>IVA</cbc:Name></cac:TaxScheme>
          </cac:TaxCategory>
        </cac:TaxSubtotal>
      </cac:TaxTotal>
      <cac:LegalMonetaryTotal>
        <cbc:LineExtensionAmount currencyID="COP">#{dinero(sale.subtotal)}</cbc:LineExtensionAmount>
        <cbc:TaxExclusiveAmount currencyID="COP">#{dinero(sale.subtotal)}</cbc:TaxExclusiveAmount>
        <cbc:TaxInclusiveAmount currencyID="COP">#{dinero(sale.total)}</cbc:TaxInclusiveAmount>
        <cbc:PayableAmount currencyID="COP">#{dinero(sale.total)}</cbc:PayableAmount>
      </cac:LegalMonetaryTotal>
    #{lineas}
      <cac:AdditionalDocumentReference>
        <cbc:ID>QR</cbc:ID>
        <cac:Attachment>
          <cbc:ExternalReference>https://catalogo-vpfe.dian.gov.co/document/searchqr?documentkey=#{esc(cufe)}</cbc:ExternalReference>
        </cac:Attachment>
      </cac:AdditionalDocumentReference>
    </Invoice>
    """
    |> String.trim_leading()
  end

  defp linea(item, indice) do
    bruto = Decimal.mult(item.unit_price, Decimal.new(item.quantity))

    """
        <cac:InvoiceLine>
          <cbc:ID>#{indice}</cbc:ID>
          <cbc:InvoicedQuantity unitCode="UN">#{item.quantity}</cbc:InvoicedQuantity>
          <cbc:LineExtensionAmount currencyID="COP">#{dinero(Decimal.sub(bruto, item.tax_amount))}</cbc:LineExtensionAmount>
          <cac:TaxTotal>
            <cbc:TaxAmount currencyID="COP">#{dinero(item.tax_amount)}</cbc:TaxAmount>
          </cac:TaxTotal>
          <cac:Item><cbc:Description>#{esc(item.product_name)}</cbc:Description></cac:Item>
          <cac:Price><cbc:PriceAmount currencyID="COP">#{dinero(item.unit_price)}</cbc:PriceAmount></cac:Price>
        </cac:InvoiceLine>
    """
    |> String.trim_trailing()
  end

  defp nombre(%{name: nombre}) when is_binary(nombre) and nombre != "", do: nombre
  defp nombre(_tenant), do: "Negocio Kubo"

  defp esc(valor) do
    valor
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
