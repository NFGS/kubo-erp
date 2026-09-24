defmodule KuboErp.Reports do
  @moduledoc """
  Reportes exportables en CSV (P-21).

  Contabilidad y bancos piden soportes; el dueño quiere su inventario en una
  hoja de calculo. Se genera CSV porque lo abre cualquier herramienta (Excel,
  LibreOffice, Google Sheets) sin dependencias.

  Las fechas del reporte de ventas se interpretan en la **zona horaria del
  negocio**: un rango "del 1 al 30" es el del negocio, no el de UTC.

  Dos cuidados propios de un archivo que se abre en Excel o Sheets:

  - **Inyeccion de formulas**: una celda que empiece por `=`, `+`, `-` o `@` se
    antepone con `'` para que la hoja la trate como texto y no ejecute formulas
    (un cliente llamado `=HYPERLINK(...)` no debe ejecutarse al abrir el archivo).
  - **Sin truncados silenciosos**: si el rango supera el maximo de filas se
    responde un error explicito en lugar de entregar un reporte incompleto.
  """

  import Ecto.Query

  alias KuboErp.{Repo, Sales}
  alias KuboErp.Catalog.Product
  alias KuboErp.Sales.Sale

  # Un reporte financiero incompleto es peor que un error: se acota y se avisa.
  @max_filas 50_000

  @doc """
  Ventas del negocio en CSV, con filtro opcional por rango de fechas.

  Devuelve `{:ok, csv}` o `{:error, mensaje}` cuando el rango no es valido o
  supera el maximo de filas (para responder 400 en lugar de un 500).
  """
  def sales_csv(tenant_id, params \\ %{}) do
    with {:ok, desde} <- validar_fecha(params["from"], "from"),
         {:ok, hasta} <- validar_fecha(params["to"], "to") do
      timezone = Sales.business_timezone()

      query =
        Sale
        |> where([s], s.tenant_id == ^tenant_id)
        |> filtrar_rango(desde, hasta, timezone)

      with :ok <- validar_tamano(query, "ventas") do
        filas =
          query
          |> order_by([s], desc: s.inserted_at)
          |> Repo.all()
          |> Enum.map(fn venta ->
            [
              venta.number,
              fecha_hora(venta.inserted_at, timezone),
              venta.customer_name || "Consumidor final",
              venta.payment_method,
              venta.status,
              dinero(venta.subtotal),
              dinero(venta.tax),
              dinero(venta.total)
            ]
          end)

        {:ok,
         a_csv(
           [
             "numero",
             "fecha",
             "cliente",
             "medio_pago",
             "estado",
             "subtotal",
             "impuesto",
             "total"
           ],
           filas
         )}
      end
    end
  end

  @doc "Inventario valorizado en CSV. Devuelve `{:ok, csv}` o `{:error, mensaje}`."
  def inventory_csv(tenant_id) do
    query =
      Product
      |> where([p], p.tenant_id == ^tenant_id and is_nil(p.deleted_at))

    with :ok <- validar_tamano(query, "productos") do
      filas =
        query
        |> order_by([p], asc: p.name)
        |> Repo.all()
        |> Enum.map(fn producto ->
          [
            producto.sku,
            producto.name,
            producto.stock,
            producto.min_stock,
            dinero(producto.cost),
            dinero(producto.price),
            dinero(Decimal.mult(producto.cost, Decimal.new(producto.stock)))
          ]
        end)

      {:ok,
       a_csv(
         ["sku", "nombre", "stock", "stock_minimo", "costo", "precio", "valor_inventario"],
         filas
       )}
    end
  end

  # ---------------------------------------------------------------------------
  # Internos
  # ---------------------------------------------------------------------------

  defp validar_tamano(query, descripcion) do
    case Repo.aggregate(query, :count) do
      total when total > @max_filas ->
        {:error,
         {:too_large,
          "el reporte tiene #{total} #{descripcion} y el maximo es #{@max_filas}; " <>
            "acota el rango o exporta por partes"}}

      _total ->
        :ok
    end
  end

  defp validar_fecha(nil, _campo), do: {:ok, nil}

  defp validar_fecha(valor, campo) do
    case Date.from_iso8601(valor) do
      {:ok, fecha} ->
        {:ok, fecha}

      {:error, _motivo} ->
        {:error, {:invalid_date, "el parametro #{campo} debe ser una fecha YYYY-MM-DD"}}
    end
  end

  defp filtrar_rango(query, desde, hasta, timezone) do
    query
    |> filtrar_desde(desde, timezone)
    |> filtrar_hasta(hasta, timezone)
  end

  defp filtrar_desde(query, nil, _timezone), do: query

  defp filtrar_desde(query, desde, timezone) do
    from(s in query,
      where:
        fragment(
          "(? AT TIME ZONE 'UTC' AT TIME ZONE ?)::date >= ?::date",
          s.inserted_at,
          ^timezone,
          ^desde
        )
    )
  end

  defp filtrar_hasta(query, nil, _timezone), do: query

  defp filtrar_hasta(query, hasta, timezone) do
    from(s in query,
      where:
        fragment(
          "(? AT TIME ZONE 'UTC' AT TIME ZONE ?)::date <= ?::date",
          s.inserted_at,
          ^timezone,
          ^hasta
        )
    )
  end

  defp fecha_hora(nil, _timezone), do: ""

  defp fecha_hora(%DateTime{} = valor, timezone) do
    valor
    |> DateTime.shift_zone!(timezone)
    |> DateTime.to_iso8601()
  rescue
    _error -> DateTime.to_iso8601(valor)
  end

  defp fecha_hora(%NaiveDateTime{} = valor, timezone) do
    valor
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.shift_zone!(timezone)
    |> DateTime.to_iso8601()
  rescue
    _error -> NaiveDateTime.to_iso8601(valor)
  end

  defp dinero(%Decimal{} = valor), do: Decimal.to_string(valor, :normal)
  defp dinero(valor), do: to_string(valor)

  defp a_csv(encabezado, filas) do
    [encabezado | filas]
    |> Enum.map_join("\n", fn fila -> Enum.map_join(fila, ",", &escapar/1) end)
    |> Kernel.<>("\n")
  end

  @formula_inicio ~r/^[=+\-@\t\r]/
  @numero ~r/^-?\d+(\.\d+)?$/

  defp escapar(nil), do: ""

  defp escapar(valor) do
    texto =
      valor
      |> to_string()
      |> neutralizar_formula()

    if String.contains?(texto, [",", "\"", "\n"]) do
      "\"" <> String.replace(texto, "\"", "\"\"") <> "\""
    else
      texto
    end
  end

  # Una celda que empieza por = + - @ la ejecutan Excel y Sheets como formula;
  # se antepone ' (marca de texto) salvo que sea un numero legitimo, que debe
  # seguir siendo numerico para las sumas.
  defp neutralizar_formula(texto) do
    if Regex.match?(@formula_inicio, texto) and not Regex.match?(@numero, texto) do
      "'" <> texto
    else
      texto
    end
  end
end
