defmodule KuboErp.Repo.Migrations.InvoiceProviderState do
  @moduledoc """
  Estado del proveedor tecnologico en la factura: su referencia externa (para
  reconciliar y reintentar sin duplicar) y el detalle del estado (por ejemplo,
  el motivo de un rechazo de la DIAN).
  """

  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add(:provider_reference, :string, size: 80)
      add(:status_detail, :string, size: 200)
    end
  end
end
