defmodule KuboErp.CreditNotes do
  @moduledoc """
  Notas credito electronicas (P-18, ADR-0014).

  Una factura es inmutable: anular una venta facturada no borra ni edita la
  factura, emite una **nota credito** que la referencia. Como la factura, la
  nota guarda su representacion emitida (CUDE y XML) y su XML queda en el
  archivo de documentos.

  La emision es idempotente por venta: si ya existe la nota se devuelve la
  misma, de modo que un reintento (o un doble clic) no emite dos documentos
  fiscales.
  """

  import Ecto.Query

  alias KuboErp.{Billing, Documents, Repo}
  alias KuboErp.Billing.CreditNote
  alias KuboErp.Invoices
  alias KuboErp.Sales
  alias KuboErp.Sales.Sale

  @doc """
  Emite la nota credito de una venta anulada y facturada.

  Devuelve `{:error, :sale_not_voided}` si la venta sigue vigente y
  `{:error, :invoice_not_found}` si nunca se facturo: sin factura no hay nada
  que corregir.
  """
  def issue(tenant_id, sale_id, tenant, razon \\ nil) do
    case get_by_sale(tenant_id, sale_id) do
      %CreditNote{} = existente ->
        {:ok, existente}

      nil ->
        emitir(tenant_id, sale_id, tenant, razon)
    end
  end

  @doc "Nota credito de la venta, si existe."
  def get_by_sale(tenant_id, sale_id) do
    CreditNote
    |> where([n], n.tenant_id == ^tenant_id and n.sale_id == ^sale_id)
    |> Repo.one()
  end

  defp emitir(tenant_id, sale_id, tenant, razon) do
    case Sales.get_sale(tenant_id, sale_id) do
      nil ->
        {:error, :sale_not_found}

      %Sale{status: status} when status != "VOIDED" ->
        {:error, :sale_not_voided}

      %Sale{} = sale ->
        case Invoices.get_by_sale(tenant_id, sale_id) do
          nil ->
            {:error, :invoice_not_found}

          factura ->
            emitir_con_factura(tenant_id, tenant, sale, factura, razon)
        end
    end
  end

  defp emitir_con_factura(tenant_id, tenant, sale, factura, razon) do
    razon = razon || "Anulacion de la venta #{sale.number}"

    with {:ok, emitida} <- Billing.issue_credit_note(tenant, sale, factura, razon) do
      # La nota y su XML se guardan juntos: una nota sin su documento seria una
      # inconsistencia que despues nadie puede reconstruir.
      Repo.scoped_transaction(fn ->
        nota =
          case %CreditNote{}
               |> CreditNote.changeset(%{
                 tenant_id: tenant_id,
                 sale_id: sale.id,
                 invoice_id: factura.id,
                 number: emitida.number,
                 cude: emitida.cude,
                 qr_url: emitida.qr_url,
                 reason: razon,
                 provider: Invoices.provider(),
                 xml: emitida.xml,
                 issued_at: DateTime.utc_now() |> DateTime.truncate(:second)
               })
               |> Repo.insert() do
            {:ok, nota} -> nota
            {:error, changeset} -> Repo.rollback(changeset)
          end

        case Documents.store(tenant_id, %{
               kind: "CREDIT_NOTE_XML",
               filename: "#{nota.number}.xml",
               content_type: "application/xml",
               content: emitida.xml,
               reference_type: "CREDIT_NOTE",
               reference_id: nota.id
             }) do
          {:ok, _documento} -> nota
          {:error, razon} -> Repo.rollback(razon)
        end
      end)
    end
  end
end
