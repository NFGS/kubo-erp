defmodule KuboErp.Invoices do
  @moduledoc """
  Emision y consulta de facturas electronicas (P-18).

  Emitir es **idempotente**: si la venta ya tiene factura se devuelve la
  existente. Una factura es un documento inmutable — regenerarla cambiaria el
  CUFE y dejaria de coincidir con el que recibio el cliente.
  """

  import Ecto.Query

  alias KuboErp.{Billing, Repo, Sales}
  alias KuboErp.Billing.Invoice
  alias KuboErp.Sales.Sale

  @doc "Emite (o devuelve) la factura de la venta con el proveedor configurado."
  def issue(tenant_id, sale_id, tenant) do
    case get_by_sale(tenant_id, sale_id) do
      %Invoice{} = existente ->
        {:ok, existente}

      nil ->
        # Una venta anulada no se factura: el camino correcto es una nota
        # credito, no un documento que ya no corresponde.
        with %Sale{status: "COMPLETED"} = sale <- Sales.get_sale(tenant_id, sale_id),
             {:ok, emitida} <- Billing.issue(tenant, sale) do
          %Invoice{}
          |> Invoice.changeset(%{
            tenant_id: tenant_id,
            sale_id: sale.id,
            number: emitida.number,
            cufe: emitida.cufe,
            qr_url: emitida.qr_url,
            provider: provider(),
            xml: emitida.xml,
            issued_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })
          |> Repo.insert()
        else
          nil -> {:error, :sale_not_found}
          %Sale{} -> {:error, :sale_voided}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def get_by_sale(tenant_id, sale_id) do
    Invoice
    |> where([i], i.tenant_id == ^tenant_id and i.sale_id == ^sale_id)
    |> Repo.one()
  end

  def get(tenant_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        Invoice
        |> where([i], i.tenant_id == ^tenant_id and i.id == ^uuid)
        |> Repo.one()

      :error ->
        nil
    end
  end

  defp provider do
    Billing.adapter() |> Module.split() |> List.last() |> Macro.underscore()
  end
end
