defmodule KuboErp.PaginationTest do
  @moduledoc "Pruebas puras de la normalizacion de paginas (P-13)."

  use ExUnit.Case, async: true

  alias KuboErp.Pagination

  test "sin parametros usa el tamano por defecto y offset cero" do
    assert Pagination.normalize(%{}) == {Pagination.default_limit(), 0}
    assert Pagination.normalize([]) == {Pagination.default_limit(), 0}
  end

  test "acepta parametros de query en texto" do
    assert Pagination.normalize(%{"limit" => "25", "offset" => "50"}) == {25, 50}
  end

  test "acepta opciones de keyword" do
    assert Pagination.normalize(limit: 10, offset: 5) == {10, 5}
  end

  test "acota el tamano de pagina al maximo del servidor" do
    assert Pagination.normalize(%{"limit" => "1000"}) == {Pagination.max_limit(), 0}
  end

  test "un limite invalido o negativo cae al minimo de una fila" do
    assert Pagination.normalize(%{"limit" => "muchos"}) == {Pagination.default_limit(), 0}
    assert Pagination.normalize(%{"limit" => "-4"}) == {1, 0}
  end

  test "un offset invalido o negativo cae a cero" do
    assert Pagination.normalize(%{"offset" => "x"}) == {Pagination.default_limit(), 0}
    assert Pagination.normalize(%{"offset" => "-9"}) == {Pagination.default_limit(), 0}
  end
end
