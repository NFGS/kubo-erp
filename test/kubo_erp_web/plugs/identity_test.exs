defmodule KuboErpWeb.Plugs.IdentityTest do
  @moduledoc """
  Identidad verificada que el gateway inyecta (P-28): formato de las cabeceras y
  whitelist de roles.
  """

  use KuboErpWeb.ConnCase, async: true

  alias KuboErpWeb.Plugs.Identity

  @tenant "11111111-1111-1111-1111-111111111111"

  test "rechaza un rol desconocido", %{conn: conn} do
    conn =
      conn
      |> put_req_header("x-tenant-id", @tenant)
      |> put_req_header("x-user-role", "SUPERADMIN")
      |> Identity.call([])

    assert conn.halted
    assert conn.status == 403
  end

  test "acepta un rol valido y lo asigna", %{conn: conn} do
    conn =
      conn
      |> put_req_header("x-tenant-id", @tenant)
      |> put_req_header("x-user-role", "SELLER")
      |> Identity.call([])

    refute conn.halted
    assert conn.assigns.user_role == "SELLER"
  end

  test "rechaza un negocio malformado", %{conn: conn} do
    conn =
      conn
      |> put_req_header("x-tenant-id", "no-es-uuid")
      |> Identity.call([])

    assert conn.halted
    assert conn.status == 400
  end
end
