defmodule KuboErp.PacksTest do
  @moduledoc """
  Paquetes de configuracion por vertical (P-17). No requieren base de datos:
  validan el catalogo que el ERP ofrece y su respaldo ante un vertical
  desconocido.
  """

  use ExUnit.Case, async: true

  alias KuboErp.Packs

  test "los cuatro verticales del plan existen y adaptan la terminologia" do
    claves = Packs.all() |> Enum.map(& &1.key) |> Enum.sort()
    assert claves == ["agro", "restaurantes", "retail", "servicios"]

    etiquetas = Packs.all() |> Enum.map(& &1.product_label)
    assert Enum.uniq(etiquetas) == etiquetas, "cada vertical debe tener su propia etiqueta"

    assert Packs.all() |> Enum.all?(&(&1.default_tax_rate =~ ~r/^\d+\.\d{2}$/))
  end

  test "un vertical desconocido cae al paquete por defecto" do
    assert Packs.get(nil).key == "retail"
    assert Packs.get("").key == "retail"
    assert Packs.get("inventado").key == "retail"
    assert Packs.default().key == "retail"
  end

  test "cada paquete describe su flujo de punto de venta" do
    assert Packs.get("restaurantes").pos_flow == "table"
    assert Packs.get("retail").pos_flow == "sale"
    assert Packs.get("servicios").tracks_stock == false
    assert Packs.get("retail").tracks_stock == true
  end
end
