defmodule KuboErp.Billing.Invoice do
  @moduledoc """
  Factura electronica emitida (P-18).

  Es un documento **inmutable**: se guarda la representacion que se entrego
  (CUFE y XML) y no se regenera. Anular una factura es un documento nuevo
  (nota credito), nunca editar el anterior.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "invoices" do
    field(:tenant_id, :binary_id)
    field(:sale_id, :binary_id)
    field(:number, :string)
    field(:cufe, :string)
    field(:qr_url, :string)
    field(:provider, :string)
    field(:status, :string, default: "ISSUED")
    field(:provider_reference, :string)
    field(:status_detail, :string)
    field(:xml, :string)
    field(:issued_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  def changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [
      :tenant_id,
      :sale_id,
      :number,
      :cufe,
      :qr_url,
      :provider,
      :status,
      :provider_reference,
      :status_detail,
      :xml,
      :issued_at
    ])
    |> validate_required([
      :tenant_id,
      :sale_id,
      :number,
      :cufe,
      :qr_url,
      :provider,
      :xml,
      :issued_at
    ])
    |> validate_length(:cufe, is: 96)
    |> unique_constraint([:tenant_id, :sale_id], name: :invoices_tenant_sale_unique)
  end
end
