defmodule KuboErp.Pagination do
  @moduledoc """
  Normaliza `limit`/`offset` de la API.

  Los listados del ERP pueden crecer sin techo (un negocio grande supera los
  cientos de productos o ventas), de modo que el servidor acota la pagina: el
  cliente nunca puede pedir la tabla completa ni forzar una consulta desmedida.
  El total real viaja en la respuesta para que la interfaz pueda paginar.
  """

  @default_limit 100
  @max_limit 200

  @doc "Devuelve `{limit, offset}` a partir de parametros de query o de opciones."
  def normalize(params) when is_map(params) do
    {limit(Map.get(params, "limit")), offset(Map.get(params, "offset"))}
  end

  def normalize(opts) when is_list(opts) do
    {limit(Keyword.get(opts, :limit)), offset(Keyword.get(opts, :offset))}
  end

  @doc "Tamano de pagina por defecto."
  def default_limit, do: @default_limit

  @doc "Tamano de pagina maximo aceptado."
  def max_limit, do: @max_limit

  defp limit(nil), do: @default_limit
  defp limit(value), do: value |> parse_int(@default_limit) |> min(@max_limit) |> max(1)

  defp offset(nil), do: 0
  defp offset(value), do: value |> parse_int(0) |> max(0)

  defp parse_int(value, _fallback) when is_integer(value), do: value

  defp parse_int(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> fallback
    end
  end

  defp parse_int(_value, fallback), do: fallback
end
