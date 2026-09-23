defmodule KuboErp.SalesTotalsTest do
  @moduledoc """
  Pruebas de la aritmetica de dinero. No requieren base de datos: validan la
  desagregacion del IVA cuando el precio al publico ya lo incluye.
  """

  use ExUnit.Case, async: true

  alias KuboErp.Sales

  test "desagrega el IVA de un precio con impuesto incluido" do
    amounts = Sales.line_amounts(2, Decimal.new("11900.00"), Decimal.new("19.00"))

    assert Decimal.equal?(amounts.total, Decimal.new("23800.00"))
    assert Decimal.equal?(amounts.tax, Decimal.new("3800.00"))
    assert Decimal.equal?(amounts.subtotal, Decimal.new("20000.00"))
  end

  test "suma los importes de varias lineas" do
    totals =
      Sales.totals([
        Sales.line_amounts(1, Decimal.new("11900.00"), Decimal.new("19.00")),
        Sales.line_amounts(3, Decimal.new("5950.00"), Decimal.new("19.00"))
      ])

    assert Decimal.equal?(totals.total, Decimal.new("41650.00"))
    assert Decimal.equal?(totals.subtotal, Decimal.new("35000.00"))
    assert Decimal.equal?(totals.tax, Decimal.new("6650.00"))
  end

  test "un producto exento de IVA no genera impuesto" do
    amounts = Sales.line_amounts(1, Decimal.new("5000.00"), Decimal.new("0.00"))

    assert Decimal.equal?(amounts.tax, Decimal.new("0.00"))
    assert Decimal.equal?(amounts.subtotal, Decimal.new("5000.00"))
    assert Decimal.equal?(amounts.total, Decimal.new("5000.00"))
  end

  test "el total siempre es la suma de subtotal e impuesto" do
    amounts = Sales.line_amounts(7, Decimal.new("3333.33"), Decimal.new("19.00"))
    suma = Decimal.add(amounts.subtotal, amounts.tax)

    assert Decimal.equal?(amounts.total, suma)
  end
end
