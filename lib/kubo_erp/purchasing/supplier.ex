defmodule KuboErp.Purchasing.Supplier do
  @moduledoc """
  Proveedor del negocio. `tax_id` es el NIT o documento tributario: es un dato
  comercial, no personal, por eso no se cifra como los clientes del CRM.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "suppliers" do
    field(:tenant_id, :binary_id)
    field(:name, :string)
    field(:tax_id, :string)
    field(:contact_name, :string)
    field(:phone, :string)
    field(:email, :string)
    field(:address, :string)
    field(:notes, :string)
    field(:active, :boolean, default: true)
    field(:deleted_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  def changeset(supplier, attrs) do
    supplier
    |> cast(attrs, [
      :tenant_id,
      :name,
      :tax_id,
      :contact_name,
      :phone,
      :email,
      :address,
      :notes,
      :active
    ])
    |> validate_required([:tenant_id, :name])
    |> validate_length(:name, max: 160)
    |> validate_format(:email, ~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/, allow_blank: true)
    |> unique_constraint(:tax_id, name: :suppliers_tenant_tax_id_unique)
  end
end
