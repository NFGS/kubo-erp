defmodule KuboErpWeb.BillingErrors do
  @moduledoc """
  Traduce los errores tipados del puerto de facturacion a respuestas HTTP.

  Un fallo de red es reintentable (`503`), un rechazo o una validacion son
  definitivos (`422`) y una operacion no soportada es `501`. Los detalles
  internos se registran, nunca se envian al cliente.
  """

  require Logger

  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn, only: [put_status: 2]

  alias KuboErp.Billing.Error

  def responder(conn, %Error{code: code, message: message, detail: detail}) do
    {status, codigo} =
      case code do
        :not_configured -> {:service_unavailable, "BILLING_NOT_CONFIGURED"}
        :not_supported -> {:not_implemented, "BILLING_NOT_SUPPORTED"}
        :network -> {:service_unavailable, "BILLING_UNAVAILABLE"}
        :rejected -> {:unprocessable_entity, "INVOICE_REJECTED"}
        :validation -> {:unprocessable_entity, "INVOICE_INVALID"}
        _ -> {:bad_gateway, "BILLING_FAILED"}
      end

    conn
    |> put_status(status)
    |> json(%{code: codigo, message: message, detail: detail})
  end

  def responder(conn, razon) do
    # Adaptadores que aun devuelven un atomo: se registra el detalle y se
    # responde un mensaje generico.
    Logger.warning("Fallo de facturacion no tipado: #{inspect(razon)}")

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "INVOICE_FAILED", message: "No fue posible emitir el documento"})
  end
end
