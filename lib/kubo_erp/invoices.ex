defmodule KuboErp.Invoices do
  @moduledoc """
  Emision y consulta de facturas electronicas (P-18).

  Emitir es **idempotente**: si la venta ya tiene factura se devuelve la
  existente. Una factura es un documento inmutable — regenerarla cambiaria el
  CUFE y dejaria de coincidir con el que recibio el cliente.
  """

  import Ecto.Query

  alias KuboErp.{Billing, Documents, Repo, Sales}
  alias KuboErp.Billing.Invoice
  alias KuboErp.Sales.Sale

  @doc "Emite (o devuelve) la factura de la venta con el proveedor configurado."
  def issue(tenant_id, sale_id, tenant) do
    case get_by_sale(tenant_id, sale_id) do
      %Invoice{} = existente ->
        {:ok, existente}

      nil ->
        # Un solo emisor por venta aunque lleguen dos peticiones a la vez (doble
        # clic, reintento): el candado por venta se libera al terminar la
        # transaccion y evita llamar dos veces al proveedor tecnologico.
        Repo.scoped_transaction(fn ->
          Repo.query!("select pg_advisory_xact_lock(hashtext($1))", [sale_id])

          case get_by_sale(tenant_id, sale_id) do
            %Invoice{} = existente ->
              existente

            nil ->
              case emitir(tenant_id, sale_id, tenant) do
                {:ok, factura} -> factura
                {:error, reason} -> Repo.rollback(reason)
              end
          end
        end)
    end
  end

  defp emitir(tenant_id, sale_id, tenant) do
    with %Sale{status: "COMPLETED"} = sale <- Sales.get_sale(tenant_id, sale_id),
         {:ok, emitida} <- Billing.issue(tenant, sale) do
      # La factura y su XML se guardan juntos: una factura sin su documento
      # seria una inconsistencia que despues nadie puede reconstruir.
      factura =
        case %Invoice{}
             |> Invoice.changeset(%{
               tenant_id: tenant_id,
               sale_id: sale.id,
               number: emitida.number,
               cufe: emitida.cufe,
               qr_url: emitida.qr_url,
               provider: provider(),
               status: Map.get(emitida, :status, "ISSUED"),
               provider_reference: Map.get(emitida, :provider_reference),
               status_detail: Map.get(emitida, :status_detail),
               xml: emitida.xml,
               issued_at: DateTime.utc_now() |> DateTime.truncate(:second)
             })
             |> Repo.insert() do
          {:ok, factura} -> factura
          {:error, changeset} -> Repo.rollback(changeset)
        end

      case Documents.store(tenant_id, %{
             kind: "INVOICE_XML",
             filename: "#{factura.number}.xml",
             content_type: "application/xml",
             content: emitida.xml,
             reference_type: "INVOICE",
             reference_id: factura.id
           }) do
        {:ok, _documento} -> {:ok, factura}
        {:error, razon} -> Repo.rollback(razon)
      end
    else
      nil -> {:error, :sale_not_found}
      %Sale{} -> {:error, :sale_voided}
      {:error, reason} -> {:error, reason}
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

  @doc "Proveedor tecnologico configurado (el adaptador de facturacion)."
  def provider do
    Billing.adapter() |> Module.split() |> List.last() |> Macro.underscore()
  end

  @doc """
  Consulta el estado en linea del documento con el proveedor (validacion
  asincrona) y lo persiste. Los proveedores que validan de forma sincrona no
  implementan esta operacion y responden `:not_supported`.
  """
  def refresh_status(tenant_id, id) do
    case get(tenant_id, id) do
      nil ->
        {:error, :invoice_not_found}

      %Invoice{} = factura ->
        case Billing.refresh_status(factura) do
          {:ok, actualizado} ->
            factura
            |> Invoice.changeset(%{
              status: Map.get(actualizado, :status, factura.status),
              status_detail: Map.get(actualizado, :status_detail, factura.status_detail),
              provider_reference:
                Map.get(actualizado, :provider_reference, factura.provider_reference)
            })
            |> Repo.update()

          {:error, razon} ->
            {:error, razon}
        end
    end
  end
end
