defmodule KuboErpWeb.WarehouseJSON do
  @moduledoc "Representacion JSON de bodegas (P-22)."

  def index(%{warehouses: warehouses}), do: %{data: Enum.map(warehouses, &data/1)}

  def show(%{warehouse: warehouse}), do: %{data: data(warehouse)}

  defp data(warehouse) do
    %{
      id: warehouse.id,
      name: warehouse.name,
      address: warehouse.address,
      is_default: warehouse.is_default,
      active: warehouse.active,
      created_at: iso(warehouse.inserted_at)
    }
  end

  defp iso(nil), do: nil
  defp iso(%DateTime{} = valor), do: DateTime.to_iso8601(valor)
  defp iso(%NaiveDateTime{} = valor), do: NaiveDateTime.to_iso8601(valor)
end
