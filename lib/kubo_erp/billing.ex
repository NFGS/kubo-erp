defmodule KuboErp.Billing do
  @moduledoc """
  Puerto de facturacion electronica (P-18, ADR-0014).

  El nucleo comercial no conoce al proveedor tecnologico de la DIAN: pide una
  factura y recibe su representacion (numero, CUFE, QR y XML). Cambiar de
  proveedor —o pasar de la habilitacion a produccion— es cambiar el adaptador
  configurado, no tocar la venta.

  El adaptador por defecto (`Sandbox`) genera un documento con la estructura
  UBL 2.1 y el CUFE calculado como lo define la DIAN, valido para desarrollo y
  para el ambiente de habilitacion; el proveedor real se enchufa implementando
  este mismo contrato.
  """

  alias KuboErp.Sales.Sale

  @callback issue(tenant :: map(), sale :: Sale.t()) ::
              {:ok, %{number: String.t(), cufe: String.t(), qr_url: String.t(), xml: String.t()}}
              | {:error, term()}

  @doc "Adaptador configurado (`KUBO_BILLING_ADAPTER`, por defecto el sandbox)."
  def adapter do
    case Application.get_env(:kubo_erp, :billing_adapter, KuboErp.Billing.Sandbox) do
      modulo when is_atom(modulo) -> modulo
    end
  end

  @doc "Emite la factura de la venta con el adaptador configurado."
  def issue(tenant, %Sale{} = sale), do: adapter().issue(tenant, sale)
end
