defmodule KuboErp.Billing.CreditNote do
  @moduledoc """
  Nota credito electronica emitida (P-18, ADR-0014).

  Documento **inmutable** que referencia la factura que corrige: se guarda la
  representacion entregada (CUDE y XML) y no se regenera.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "credit_notes" do
    field(:tenant_id, :binary_id)
    field(:sale_id, :binary_id)
    field(:invoice_id, :binary_id)
    field(:number, :string)
    field(:cude, :string)
    field(:qr_url, :string)
    field(:reason, :string)
    field(:provider, :string)
    field(:xml, :string)
    field(:issued_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  def changeset(nota, attrs) do
    nota
    |> cast(attrs, [
      :tenant_id,
      :sale_id,
      :invoice_id,
      :number,
      :cude,
      :qr_url,
      :reason,
      :provider,
      :xml,
      :issued_at
    ])
    |> validate_required([
      :tenant_id,
      :sale_id,
      :invoice_id,
      :number,
      :cude,
      :qr_url,
      :reason,
      :provider,
      :xml,
      :issued_at
    ])
    |> validate_length(:cude, is: 96)
    |> unique_constraint([:tenant_id, :sale_id], name: :credit_notes_tenant_sale_unique)
  end
end
