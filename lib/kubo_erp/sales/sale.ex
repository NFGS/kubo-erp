defmodule KuboErp.Sales.Sale do
  @moduledoc "Venta (documento comercial). El detalle vive en `sale_items`."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w[COMPLETED VOIDED]
  @payment_methods ~w[CASH CARD TRANSFER CREDIT]

  schema "sales" do
    field :tenant_id, :binary_id
    field :number, :string
    field :customer_id, :binary_id
    field :customer_name, :string
    field :status, :string, default: "COMPLETED"
    field :payment_method, :string, default: "CASH"
    field :subtotal, :decimal, default: Decimal.new(0)
    field :tax, :decimal, default: Decimal.new(0)
    field :total, :decimal, default: Decimal.new(0)
    field :notes, :string
    field :sold_by, :binary_id
    field :voided_at, :utc_datetime

    has_many :items, KuboErp.Sales.SaleItem, foreign_key: :sale_id

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def payment_methods, do: @payment_methods

  def changeset(sale, attrs) do
    sale
    |> cast(attrs, [
      :tenant_id,
      :number,
      :customer_id,
      :customer_name,
      :status,
      :payment_method,
      :subtotal,
      :tax,
      :total,
      :notes,
      :sold_by,
      :voided_at
    ])
    |> validate_required([:tenant_id, :number, :total])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:payment_method, @payment_methods)
    |> validate_number(:total, greater_than_or_equal_to: 0)
    |> unique_constraint([:tenant_id, :number], message: "numero de venta duplicado")
  end
end
