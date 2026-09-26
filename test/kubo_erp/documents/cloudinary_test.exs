defmodule KuboErp.Documents.Storage.CloudinaryTest do
  @moduledoc """
  Adaptador de objetos (P-25). No toca la red: valida la firma —que es el
  contrato con Cloudinary— y la URL determinista de descarga.
  """

  use ExUnit.Case, async: true

  alias KuboErp.Documents.Storage.Cloudinary

  test "la firma es el SHA-1 de los parametros ordenados mas el secreto" do
    parametros = %{"public_id" => "negocio-1/doc-1", "timestamp" => 1_315_060_510}

    # Cadena construida a mano (no con el ayudante del adaptador) para probar el
    # algoritmo y no la implementacion contra si misma.
    esperada =
      :sha
      |> :crypto.hash("public_id=negocio-1/doc-1&timestamp=1315060510abcd")
      |> Base.encode16(case: :lower)

    assert Cloudinary.firma(parametros, "abcd") == esperada
    assert Cloudinary.firma(parametros, "abcd") =~ ~r/^[0-9a-f]{40}$/
    assert Cloudinary.firma(parametros, "otro") != esperada
  end

  test "la URL de descarga es determinista a partir de la clave" do
    assert Cloudinary.url_de("kubo", "negocio-1/doc-1") ==
             "https://res.cloudinary.com/kubo/raw/upload/negocio-1/doc-1"
  end

  test "sin configuracion falla con un error claro" do
    Application.delete_env(:kubo_erp, :cloudinary_url)
    System.delete_env("KUBO_CLOUDINARY_URL")

    assert {:error, :cloudinary_not_configured} = Cloudinary.put("negocio-1/doc-1", "x")
    assert {:error, :cloudinary_not_configured} = Cloudinary.get("negocio-1/doc-1")
  end
end
