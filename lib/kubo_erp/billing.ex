defmodule KuboErp.Billing do
  @moduledoc """
  Puerto de facturacion electronica (P-18, ADR-0014).

  El nucleo comercial no conoce al proveedor tecnologico de la DIAN: pide una
  factura y recibe su representacion (numero, CUFE, QR y XML). Cambiar de
  proveedor —o pasar de la habilitacion a produccion— es cambiar el adaptador
  configurado, no tocar la venta.

  ## Configuracion

  - `KUBO_BILLING_ADAPTER` — modulo del adaptador (por defecto
    `KuboErp.Billing.Sandbox`). Si no implementa el puerto, el servicio falla al
    arrancar en vez de emitir documentos invalidos.
  - `KUBO_BILLING_ENVIRONMENT` — ambiente DIAN: `1` produccion, `2` habilitacion
    (por defecto `2`).

  ## Contrato

  Un adaptador implementa `c:issue/2` y `c:issue_credit_note/4`; puede ademas
  implementar `c:refresh_status/1` si su proveedor reporta el estado en linea
  (validacion asincrona). Los errores se devuelven como
  `KuboErp.Billing.Error` para que la capa web los traduzca sin adivinar.

  El adaptador por defecto (`Sandbox`) genera un documento con la estructura
  UBL 2.1 y el CUFE calculado como lo define la DIAN, valido para desarrollo y
  para el ambiente de habilitacion; el proveedor real se enchufa implementando
  este mismo contrato. La guia paso a paso vive en
  `kubo-docs/13-guia-adaptador-facturacion.md`.
  """

  alias KuboErp.Billing.Error
  alias KuboErp.Billing.Invoice
  alias KuboErp.Sales.Sale

  @typedoc "Datos del negocio que recibe el adaptador (nombre y datos fiscales)."
  @type tenant :: %{
          optional(atom()) => term(),
          id: String.t(),
          name: String.t() | nil
        }

  @typedoc "Representacion emitida de una factura o nota credito."
  @type emitted :: %{
          optional(atom()) => term(),
          number: String.t(),
          qr_url: String.t(),
          xml: String.t(),
          status: String.t(),
          provider_reference: String.t() | nil,
          status_detail: String.t() | nil
        }

  @callback issue(tenant(), sale :: Sale.t()) ::
              {:ok, emitted()} | {:error, Error.t() | term()}

  @callback issue_credit_note(tenant(), sale :: Sale.t(), invoice :: map(), reason :: String.t()) ::
              {:ok, emitted()} | {:error, Error.t() | term()}

  @callback refresh_status(invoice :: Invoice.t()) ::
              {:ok, map()} | {:error, Error.t() | term()}

  @optional_callbacks refresh_status: 1

  @doc """
  Adaptador configurado. Si el modulo no implementa el puerto, se falla al
  arrancar: es mejor no emitir que emitir con un adaptador equivocado.
  """
  def adapter do
    modulo = Application.get_env(:kubo_erp, :billing_adapter, KuboErp.Billing.Sandbox)

    unless is_atom(modulo) and Code.ensure_loaded?(modulo) and function_exported?(modulo, :issue, 2) do
      raise ArgumentError,
            "KUBO_BILLING_ADAPTER no implementa el puerto de facturacion: #{inspect(modulo)}"
    end

    modulo
  end

  @doc "Emite la factura de la venta con el adaptador configurado."
  def issue(tenant, %Sale{} = sale), do: adapter().issue(tenant, sale)

  @doc "Ambiente DIAN configurado: `1` produccion, `2` habilitacion."
  def environment, do: Application.get_env(:kubo_erp, :billing_environment, "2")

  @doc """
  Emite la nota credito que corrige una factura (anulacion de la venta).

  Una factura no se edita ni se borra: se corrige con un documento nuevo que la
  referencia, y ese documento tambien tiene su representacion emitida (CUDE).
  """
  def issue_credit_note(tenant, %Sale{} = sale, invoice, reason) do
    adapter().issue_credit_note(tenant, sale, invoice, reason)
  end

  @doc """
  Consulta el estado en linea del documento (proveedores con validacion
  asincrona). Si el adaptador no lo implementa, devuelve `:not_supported`.
  """
  def refresh_status(%Invoice{} = invoice) do
    modulo = adapter()

    if Code.ensure_loaded?(modulo) and function_exported?(modulo, :refresh_status, 1) do
      modulo.refresh_status(invoice)
    else
      {:error, Error.new(:not_supported, "El proveedor configurado no reporta estado en linea")}
    end
  end
end
