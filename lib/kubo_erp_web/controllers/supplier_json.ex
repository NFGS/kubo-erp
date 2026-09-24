defmodule KuboErpWeb.SupplierJSON do
  @moduledoc "Representacion JSON de proveedores."

  def index(%{suppliers: suppliers, total: total, limit: limit, offset: offset}) do
    %{
      data: Enum.map(suppliers, &data/1),
      total: total,
      limit: limit,
      offset: offset
    }
  end

  def show(%{supplier: supplier}), do: %{data: data(supplier)}

  defp data(supplier) do
    %{
      id: supplier.id,
      name: supplier.name,
      tax_id: supplier.tax_id,
      contact_name: supplier.contact_name,
      phone: supplier.phone,
      email: supplier.email,
      address: supplier.address,
      notes: supplier.notes,
      active: supplier.active,
      created_at: iso(supplier.inserted_at),
      updated_at: iso(supplier.updated_at)
    }
  end

  defp iso(nil), do: nil
  defp iso(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
