defmodule KuboErp.Plans do
  @moduledoc """
  Cupos por plan comercial (ADR-0021).

  Espejo del catalogo de IAM: el plan viaja en el token (`x-tenant-plan`) y cada
  servicio aplica los cupos de los recursos que **posee** —aqui, las bodegas—.
  Duplicar una tabla de dos numeros es mas barato, y mas honesto, que un servicio
  de cuotas en el camino de cada peticion.

  Un plan desconocido se trata como el mas restrictivo: un dato migrado no debe
  regalar cupo.
  """

  @planes %{
    "community" => %{code: "community", max_warehouses: 2},
    "pro" => %{code: "pro", max_warehouses: 10}
  }

  def all, do: Map.values(@planes)

  def get(nil), do: @planes["community"]
  def get(""), do: @planes["community"]
  def get(plan), do: Map.get(@planes, plan, @planes["community"])
end
