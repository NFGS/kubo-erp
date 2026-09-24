defmodule KuboErp.Cash.CashSession do
  @moduledoc """
  Turno de caja: apertura con base, cierre con arqueo.

  `expected_amount` es lo que deberia haber en la caja (base + ventas en
  efectivo del turno − anuladas); `counted_amount` lo que el cajero conto, y
  `difference` la resta. La diferencia queda registrada: el arqueo no se
  "cuadra" editando el dato.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "cash_sessions" do
    field(:tenant_id, :binary_id)
    field(:status, :string, default: "OPEN")
    field(:opened_by, :binary_id)
    field(:opened_at, :utc_datetime)
    field(:opening_amount, :decimal)
    field(:closed_by, :binary_id)
    field(:closed_at, :utc_datetime)
    field(:counted_amount, :decimal)
    field(:expected_amount, :decimal)
    field(:difference, :decimal)
    field(:notes, :string)

    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :tenant_id,
      :status,
      :opened_by,
      :opened_at,
      :opening_amount,
      :closed_by,
      :closed_at,
      :counted_amount,
      :expected_amount,
      :difference,
      :notes
    ])
    |> validate_required([:tenant_id, :status, :opened_at, :opening_amount])
    |> validate_inclusion(:status, ["OPEN", "CLOSED"])
    |> validate_number(:opening_amount, greater_than_or_equal_to: 0)
    |> validate_number(:counted_amount, greater_than_or_equal_to: 0)
  end
end
