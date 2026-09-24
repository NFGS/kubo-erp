defmodule KuboErpWeb.TransferJSON do
  @moduledoc "Representacion JSON de transferencias entre bodegas (P-22)."

  def index(%{transfers: transfers}), do: %{data: Enum.map(transfers, &data/1)}

  def show(%{transfer: transfer}), do: %{data: data(transfer)}

  defp data(transfer) do
    %{
      id: transfer.id,
      from_warehouse_id: transfer.from_warehouse_id,
      to_warehouse_id: transfer.to_warehouse_id,
      status: transfer.status,
      notes: transfer.notes,
      completed_at: iso(transfer.completed_at),
      created_at: iso(transfer.inserted_at),
      items: Enum.map(transfer.items || [], &item/1)
    }
  end

  defp item(item) do
    %{product_id: item.product_id, quantity: item.quantity}
  end

  defp iso(nil), do: nil
  defp iso(%DateTime{} = valor), do: DateTime.to_iso8601(valor)
  defp iso(%NaiveDateTime{} = valor), do: NaiveDateTime.to_iso8601(valor)
end
