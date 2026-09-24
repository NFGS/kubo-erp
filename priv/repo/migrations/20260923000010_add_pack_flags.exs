defmodule KuboErp.Repo.Migrations.AddPackFlags do
  use Ecto.Migration

  @moduledoc """
  Banderas que un vertical pack ajusta (P-17, ADR-0013).

  - `products.tracks_stock`: un servicio no lleva inventario; su venta no mueve
    kardex ni exige existencias. El valor por defecto (true) mantiene el
    comportamiento del retail y del agro.
  - `sales.table_number`: el flujo de restaurante (`pos_flow: "table"`) registra
    la mesa o cuenta en la venta.
  """

  def change do
    alter table(:products) do
      add(:tracks_stock, :boolean, null: false, default: true)
    end

    alter table(:sales) do
      add(:table_number, :string, size: 20)
    end
  end
end
