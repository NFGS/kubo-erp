defmodule KuboErp.PlansTest do
  @moduledoc "Cupos por plan comercial (ADR-0021). Sin base de datos."

  use ExUnit.Case, async: true

  alias KuboErp.Plans

  test "cada plan declara su cupo de bodegas" do
    claves = Plans.all() |> Enum.map(& &1.code) |> Enum.sort()
    assert claves == ["community", "pro"]
    assert Plans.get("community").max_warehouses == 2
    assert Plans.get("pro").max_warehouses == 10
  end

  test "un plan desconocido se trata como el mas restrictivo" do
    assert Plans.get(nil).code == "community"
    assert Plans.get("").code == "community"
    assert Plans.get("inventado").code == "community"
  end
end
