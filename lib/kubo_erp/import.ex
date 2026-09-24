defmodule KuboErp.Import do
  @moduledoc """
  Importacion de catalogo desde CSV (P-24).

  Un negocio no puede cargar cientos de productos a mano: exporta su catalogo
  actual a CSV (Excel exporta CSV; tambien sirve la ruta Dolibarr) y lo sube.

  Reglas:
    * La cabecera define las columnas y acepta nombres en espanol o ingles
      (`sku`, `nombre`/`name`, `precio`/`price`, `costo`/`cost`, `stock`,
      `stock_minimo`/`min_stock`, `iva`/`tax_rate`).
    * El separador se detecta: coma, o punto y coma cuando la cabecera no trae
      comas (Excel en espanol).
    * Si el SKU existe se **actualiza**; si no, se **crea**.
    * El stock no se escribe directo: entra por el kardex con el motivo
      «Importacion de catalogo», para que la proyeccion y el historial cuadren.
    * Cada fila se procesa en su propia transaccion: una fila mala no tumba la
      importacion completa; se informa con su numero de linea.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias KuboErp.{Catalog, Repo}
  alias KuboErp.Catalog.Product

  @max_rows 1000

  @header_aliases %{
    "sku" => "sku",
    "codigo" => "sku",
    "name" => "name",
    "nombre" => "name",
    "descripcion" => "description",
    "description" => "description",
    "precio" => "price",
    "price" => "price",
    "costo" => "cost",
    "cost" => "cost",
    "iva" => "tax_rate",
    "tax_rate" => "tax_rate",
    "stock" => "stock",
    "existencia" => "stock",
    "stock_minimo" => "min_stock",
    "min_stock" => "min_stock",
    "unidad" => "unit",
    "unit" => "unit"
  }

  def import_products(tenant_id, user_id, csv) when is_binary(csv) do
    lineas =
      csv
      |> String.replace("\r\n", "\n")
      |> String.split("\n")
      |> Enum.reject(&(String.trim(&1) == ""))

    case lineas do
      [] ->
        {:error, :empty_csv}

      [cabecera | filas] ->
        cond do
          filas == [] -> {:error, :empty_csv}
          length(filas) > @max_rows -> {:error, :too_many_rows}
          true -> {:ok, procesar(tenant_id, user_id, cabecera, filas)}
        end
    end
  end

  def import_products(_tenant_id, _user_id, _csv), do: {:error, :empty_csv}

  # ---------------------------------------------------------------------------
  # Internos
  # ---------------------------------------------------------------------------

  defp procesar(tenant_id, user_id, cabecera, filas) do
    separador = separador(cabecera)
    columnas = cabecera |> String.split(separador) |> Enum.map(&normalizar_cabecera/1)

    {creados, actualizados, errores} =
      filas
      |> Enum.with_index(2)
      |> Enum.reduce({0, 0, []}, fn {linea, numero}, {creados, actualizados, errores} ->
        case importar_fila(tenant_id, user_id, columnas, linea, separador) do
          :created ->
            {creados + 1, actualizados, errores}

          :updated ->
            {creados, actualizados + 1, errores}

          {:error, mensaje} ->
            {creados, actualizados, errores ++ [%{line: numero, message: mensaje}]}
        end
      end)

    %{created: creados, updated: actualizados, errors: errores}
  end

  defp importar_fila(tenant_id, user_id, columnas, linea, separador) do
    valores = linea |> String.split(separador) |> Enum.map(&limpiar/1)
    fila = columnas |> Enum.zip(valores) |> Map.new()

    sku = fila["sku"]
    nombre = fila["name"]

    cond do
      not presente?(sku) ->
        {:error, "falta el SKU"}

      not presente?(nombre) ->
        {:error, "falta el nombre"}

      true ->
        attrs =
          %{"sku" => sku, "name" => nombre}
          |> put_if(fila["description"], "description")
          |> put_if(fila["price"], "price")
          |> put_if(fila["cost"], "cost")
          |> put_if(fila["tax_rate"], "tax_rate")
          |> put_if(fila["min_stock"], "min_stock")
          |> put_if(fila["unit"], "unit")

        case buscar(tenant_id, sku) do
          nil -> crear(tenant_id, user_id, attrs, parse_entero(fila["stock"]))
          producto -> actualizar(producto, attrs, parse_entero(fila["stock"]), user_id)
        end
    end
  end

  defp buscar(tenant_id, sku) do
    Product
    |> where([p], p.tenant_id == ^tenant_id and p.sku == ^sku and is_nil(p.deleted_at))
    |> Repo.one()
  end

  defp crear(tenant_id, user_id, attrs, stock) do
    case Repo.transaction(fn ->
           case Catalog.create_product(tenant_id, attrs) do
             {:ok, producto} ->
               if is_integer(stock) and stock > 0 do
                 case Catalog.move_stock(producto, stock,
                        kind: "IN",
                        reason: "Importacion de catalogo",
                        reference_type: "IMPORT",
                        created_by: user_id
                      ) do
                   {:ok, _producto, _movimiento} -> :ok
                   {:error, razon} -> Repo.rollback(razon)
                 end
               end

               :ok

             {:error, changeset} ->
               Repo.rollback(changeset)
           end
         end) do
      {:ok, _} -> :created
      {:error, %Changeset{} = changeset} -> {:error, mensaje_changeset(changeset)}
      {:error, razon} -> {:error, inspect(razon)}
    end
  end

  defp actualizar(producto, attrs, stock, user_id) do
    case Repo.transaction(fn ->
           case Catalog.update_product(producto, attrs) do
             {:ok, actualizado} ->
               if is_integer(stock) and stock >= 0 and stock != actualizado.stock do
                 case Catalog.move_stock(actualizado, stock - actualizado.stock,
                        kind: "ADJUST",
                        reason: "Importacion de catalogo",
                        reference_type: "IMPORT",
                        created_by: user_id
                      ) do
                   {:ok, _producto, _movimiento} -> :ok
                   {:error, razon} -> Repo.rollback(razon)
                 end
               end

               :ok

             {:error, changeset} ->
               Repo.rollback(changeset)
           end
         end) do
      {:ok, _} -> :updated
      {:error, %Changeset{} = changeset} -> {:error, mensaje_changeset(changeset)}
      {:error, razon} -> {:error, inspect(razon)}
    end
  end

  defp separador(cabecera) do
    if String.contains?(cabecera, ";") and not String.contains?(cabecera, ","), do: ";", else: ","
  end

  defp normalizar_cabecera(valor) do
    clave =
      valor
      |> limpiar()
      |> String.downcase()
      |> String.replace(~r/\s+/, "_")

    Map.get(@header_aliases, clave)
  end

  defp limpiar(valor) do
    valor
    |> to_string()
    |> String.trim()
    |> String.trim("\"")
  end

  defp presente?(valor), do: is_binary(valor) and valor != ""

  defp put_if(attrs, valor, _clave) when valor in [nil, ""], do: attrs
  defp put_if(attrs, valor, clave), do: Map.put(attrs, clave, valor)

  defp parse_entero(nil), do: nil

  defp parse_entero(valor) do
    case Integer.parse(String.replace(valor, [" ", "."], "")) do
      {entero, ""} -> entero
      _ -> nil
    end
  end

  defp mensaje_changeset(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {campo, {mensaje, _opts}} ->
      "#{campo} #{mensaje}"
    end)
  end
end
