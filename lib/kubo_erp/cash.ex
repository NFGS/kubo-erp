defmodule KuboErp.Cash do
  @moduledoc """
  Caja del negocio (P-16).

  Una sola sesion abierta por negocio (garantizado por indice unico parcial).
  Las ventas se ligan a la sesion abierta al momento de cobrar, de modo que el
  arqueo suma exactamente las ventas del turno.

  El esperado en caja es: base + ventas en efectivo completadas − ventas en
  efectivo anuladas del turno. Las ventas con tarjeta o transferencia no entran
  al efectivo (se informan aparte).
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias KuboErp.{Pagination, Repo}
  alias KuboErp.Cash.CashSession
  alias KuboErp.Sales.Sale

  # ---------------------------------------------------------------------------
  # Consultas
  # ---------------------------------------------------------------------------

  def current(tenant_id) do
    CashSession
    |> where([c], c.tenant_id == ^tenant_id and c.status == "OPEN")
    |> Repo.one()
    |> case do
      nil -> nil
      session -> %{session: session, summary: summary(session)}
    end
  end

  def get(_tenant_id, nil), do: nil

  def get(tenant_id, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id) do
      CashSession
      |> where([c], c.tenant_id == ^tenant_id and c.id == ^uuid)
      |> Repo.one()
    else
      :error -> nil
    end
  end

  def detail(tenant_id, id) do
    case get(tenant_id, id) do
      nil -> nil
      session -> %{session: session, summary: summary(session)}
    end
  end

  def list(tenant_id, opts \\ []) do
    {limit, offset} = Pagination.normalize(opts)

    CashSession
    |> where([c], c.tenant_id == ^tenant_id)
    |> order_by([c], desc: c.opened_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  def count(tenant_id) do
    CashSession |> where([c], c.tenant_id == ^tenant_id) |> Repo.aggregate(:count)
  end

  @doc "Id de la sesion abierta, o nil. Lo usa la venta para ligarse al turno."
  def open_session_id(tenant_id) do
    CashSession
    |> where([c], c.tenant_id == ^tenant_id and c.status == "OPEN")
    |> select([c], c.id)
    |> Repo.one()
  end

  # ---------------------------------------------------------------------------
  # Comandos
  # ---------------------------------------------------------------------------

  def open(tenant_id, user_id, attrs) do
    if open_session_id(tenant_id) do
      {:error, :already_open}
    else
      %CashSession{tenant_id: tenant_id}
      |> CashSession.changeset(%{
        status: "OPEN",
        opened_by: user_id,
        opened_at: DateTime.utc_now() |> DateTime.truncate(:second),
        opening_amount: parse_decimal(attrs["opening_amount"]) || Decimal.new(0),
        notes: attrs["notes"]
      })
      |> Repo.insert()
      |> case do
        {:ok, session} -> {:ok, session}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  def close(tenant_id, user_id, id, attrs) do
    case get(tenant_id, id) do
      nil ->
        {:error, :not_found}

      %CashSession{status: "CLOSED"} ->
        {:error, :already_closed}

      %CashSession{} = session ->
        resumen = summary(session)
        counted = parse_decimal(attrs["counted_amount"]) || Decimal.new(0)

        session
        |> Changeset.change(
          status: "CLOSED",
          closed_by: user_id,
          closed_at: DateTime.utc_now() |> DateTime.truncate(:second),
          counted_amount: counted,
          expected_amount: resumen.expected_cash,
          difference: Decimal.sub(counted, resumen.expected_cash),
          notes: attrs["notes"] || session.notes
        )
        |> Repo.update()
    end
  end

  # ---------------------------------------------------------------------------
  # Arqueo
  # ---------------------------------------------------------------------------

  @doc """
  Resumen del turno: ventas ligadas a la sesion, efectivo esperado y desglose.

  Las anuladas restan del efectivo (no se cobro) pero siguen contando en el
  listado para la revision del cajero.
  """
  def summary(%CashSession{} = session) do
    base =
      from(s in Sale,
        where: s.tenant_id == ^session.tenant_id and s.cash_session_id == ^session.id
      )

    completed = from(s in base, where: s.status == "COMPLETED")
    voided = from(s in base, where: s.status == "VOIDED")

    cash_completed = from(s in completed, where: s.payment_method == "CASH")
    cash_voided = from(s in voided, where: s.payment_method == "CASH")

    cash_sales = sum(cash_completed)
    cash_returns = sum(cash_voided)
    other_sales = sum(from(s in completed, where: s.payment_method != "CASH"))

    %{
      sales_count: Repo.aggregate(completed, :count),
      voided_count: Repo.aggregate(voided, :count),
      total_sales: sum_all(completed),
      cash_sales: cash_sales,
      other_sales: other_sales,
      cash_returns: cash_returns,
      expected_cash:
        Decimal.sub(Decimal.add(session.opening_amount, cash_sales), cash_returns)
        |> Decimal.round(2)
    }
  end

  defp sum(query) do
    Repo.one(from(s in query, select: coalesce(sum(s.total), 0))) |> to_decimal()
  end

  defp sum_all(query) do
    Repo.one(from(s in query, select: coalesce(sum(s.total), 0))) |> to_decimal()
  end

  defp parse_decimal(nil), do: nil

  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end

  defp parse_decimal(%Decimal{} = value), do: value
  defp parse_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp parse_decimal(_value), do: nil

  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value), do: Decimal.new(to_string(value))
end
