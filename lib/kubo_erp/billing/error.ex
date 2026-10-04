defmodule KuboErp.Billing.Error do
  @moduledoc """
  Error tipado del puerto de facturacion (ADR-0014).

  Los adaptadores devuelven `{:error, %KuboErp.Billing.Error{}}` para que la capa
  web distinga un fallo transitorio de red (`:network`, reintentable) de un
  rechazo del proveedor (`:rejected`) o de una validacion (`:validation`), sin
  filtrar detalles internos al cliente.

  Codigos previstos:

  - `:not_configured` — no hay adaptador real configurado.
  - `:not_supported` — el proveedor no ofrece esa operacion (p. ej. consultar estado).
  - `:network` — el proveedor no respondio; se puede reintentar.
  - `:rejected` — el proveedor o la DIAN rechazaron el documento.
  - `:validation` — los datos no cumplen el contrato del proveedor.
  """

  @enforce_keys [:code, :message]
  defstruct [:code, :message, :detail]

  @type t :: %__MODULE__{
          code: atom(),
          message: String.t(),
          detail: String.t() | nil
        }

  def new(code, message, detail \\ nil) do
    %__MODULE__{code: code, message: message, detail: detail}
  end
end
