defmodule KuboErpWeb.CashSessionJSON do
  @moduledoc "Representacion JSON de las sesiones de caja y su arqueo."

  def index(%{sessions: sessions, total: total, limit: limit, offset: offset}) do
    %{
      data: Enum.map(sessions, &data/1),
      total: total,
      limit: limit,
      offset: offset
    }
  end

  def detail(%{session: session, summary: summary}) do
    %{data: Map.put(data(session), :summary, summary)}
  end

  defp data(session) do
    %{
      id: session.id,
      status: session.status,
      opened_by: session.opened_by,
      opened_at: iso(session.opened_at),
      opening_amount: money(session.opening_amount),
      closed_by: session.closed_by,
      closed_at: iso(session.closed_at),
      counted_amount: money(session.counted_amount),
      expected_amount: money(session.expected_amount),
      difference: money(session.difference),
      notes: session.notes
    }
  end

  defp money(nil), do: nil
  defp money(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp money(value), do: value

  defp iso(nil), do: nil
  defp iso(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
