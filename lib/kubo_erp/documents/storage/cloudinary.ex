defmodule KuboErp.Documents.Storage.Cloudinary do
  @moduledoc """
  Almacenamiento de objetos en Cloudinary (P-25, ADR-0018).

  Se selecciona con `KUBO_DOCUMENTS_STORAGE=cloudinary` y se configura con
  `KUBO_CLOUDINARY_URL` (`cloudinary://clave:secreto@nube`). Los documentos se
  suben como recurso **raw** (no son imagenes) con firma SHA-1.

  La clave del documento es su `public_id`, de modo que la URL de descarga es
  determinista (`https://res.cloudinary.com/<nube>/raw/upload/<clave>`): la
  lectura no necesita credenciales ni una llamada extra a la API.
  """

  @behaviour KuboErp.Documents.Storage

  @impl true
  def put(key, content) do
    with {:ok, config} <- configuracion() do
      timestamp = System.system_time(:second)
      parametros = %{"public_id" => key, "timestamp" => timestamp}

      cuerpo =
        Map.merge(parametros, %{
          "api_key" => config.key,
          "signature" => firma(parametros, config.secret),
          "file" => "data:application/octet-stream;base64," <> Base.encode64(content)
        })
        |> URI.encode_query()

      case :hackney.request(
             :post,
             "https://api.cloudinary.com/v1_1/#{config.cloud}/raw/upload",
             [{"content-type", "application/x-www-form-urlencoded"}],
             cuerpo,
             []
           ) do
        {:ok, 200, _headers, ref} ->
          :hackney.body(ref)
          :ok

        {:ok, status, _headers, ref} ->
          {:error, {:cloudinary, status, resumen(:hackney.body(ref))}}

        {:error, razon} ->
          {:error, razon}
      end
    end
  end

  @impl true
  def get(key) do
    with {:ok, config} <- configuracion(),
         url = url_de(config.cloud, key),
         {:ok, 200, _headers, ref} <- :hackney.request(:get, url, [], "", []) do
      :hackney.body(ref)
    else
      {:ok, status, _headers, _ref} -> {:error, {:cloudinary, status}}
      {:error, razon} -> {:error, razon}
    end
  end

  @impl true
  def delete(key) do
    with {:ok, config} <- configuracion() do
      timestamp = System.system_time(:second)
      parametros = %{"public_id" => key, "timestamp" => timestamp, "type" => "upload"}

      cuerpo =
        Map.merge(parametros, %{
          "api_key" => config.key,
          "signature" => firma(parametros, config.secret)
        })
        |> URI.encode_query()

      case :hackney.request(
             :post,
             "https://api.cloudinary.com/v1_1/#{config.cloud}/raw/destroy",
             [{"content-type", "application/x-www-form-urlencoded"}],
             cuerpo,
             []
           ) do
        {:ok, 200, _headers, ref} ->
          :hackney.body(ref)
          :ok

        {:ok, status, _headers, ref} ->
          {:error, {:cloudinary, status, resumen(:hackney.body(ref))}}

        {:error, razon} ->
          {:error, razon}
      end
    end
  end

  @doc "Firma SHA-1 de los parametros ordenados (algoritmo de Cloudinary)."
  def firma(parametros, secreto) do
    cadena =
      parametros
      |> Enum.sort()
      |> Enum.map_join("&", fn {clave, valor} -> "#{clave}=#{valor}" end)

    :sha
    |> :crypto.hash(cadena <> secreto)
    |> Base.encode16(case: :lower)
  end

  @doc "URL determinista de descarga de un documento."
  def url_de(nube, clave), do: "https://res.cloudinary.com/#{nube}/raw/upload/#{clave}"

  defp configuracion do
    case Application.get_env(:kubo_erp, :cloudinary_url) || System.get_env("KUBO_CLOUDINARY_URL") do
      nil ->
        {:error, :cloudinary_not_configured}

      url ->
        case URI.parse(url) do
          %URI{scheme: "cloudinary", userinfo: userinfo, host: nube}
          when is_binary(userinfo) and is_binary(nube) ->
            case String.split(userinfo, ":", parts: 2) do
              [key, secret] when key != "" and secret != "" ->
                {:ok, %{key: key, secret: secret, cloud: nube}}

              _ ->
                {:error, :cloudinary_not_configured}
            end

          _ ->
            {:error, :cloudinary_not_configured}
        end
    end
  end

  defp resumen({:ok, cuerpo}), do: String.slice(cuerpo, 0, 200)
  defp resumen(_otro), do: nil
end
