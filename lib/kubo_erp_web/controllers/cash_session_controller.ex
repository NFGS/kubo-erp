defmodule KuboErpWeb.CashSessionController do
  @moduledoc "Apertura, cierre y arqueo de la caja (P-16)."

  use KuboErpWeb, :controller

  alias KuboErp.{Cash, Pagination}

  def current(conn, _params) do
    case Cash.current(conn.assigns.tenant_id) do
      nil ->
        json(conn, %{data: nil})

      %{session: session, summary: summary} ->
        render(conn, :detail, session: session, summary: summary)
    end
  end

  def index(conn, params) do
    {limit, offset} = Pagination.normalize(params)
    sessions = Cash.list(conn.assigns.tenant_id, limit: limit, offset: offset)
    total = Cash.count(conn.assigns.tenant_id)

    render(conn, :index, sessions: sessions, total: total, limit: limit, offset: offset)
  end

  def show(conn, %{"id" => id}) do
    case Cash.detail(conn.assigns.tenant_id, id) do
      nil ->
        error(conn, :not_found, "CASH_SESSION_NOT_FOUND", "La sesion de caja no existe")

      %{session: session, summary: summary} ->
        render(conn, :detail, session: session, summary: summary)
    end
  end

  def open(conn, params) do
    attrs = params["cash_session"] || params

    case Cash.open(conn.assigns.tenant_id, conn.assigns.user_id, attrs) do
      {:ok, session} ->
        conn
        |> put_status(:created)
        |> render(:detail, session: session, summary: Cash.summary(session))

      {:error, :already_open} ->
        error(conn, :conflict, "CASH_ALREADY_OPEN", "Ya hay una caja abierta en este negocio")

      {:error, changeset} ->
        error(conn, :unprocessable_entity, "VALIDATION_ERROR", inspect(changeset.errors))
    end
  end

  def close(conn, %{"id" => id} = params) do
    attrs = params["cash_session"] || params

    case Cash.close(conn.assigns.tenant_id, conn.assigns.user_id, id, attrs) do
      {:ok, session} ->
        render(conn, :detail, session: session, summary: Cash.summary(session))

      {:error, :not_found} ->
        error(conn, :not_found, "CASH_SESSION_NOT_FOUND", "La sesion de caja no existe")

      {:error, :already_closed} ->
        error(conn, :conflict, "CASH_ALREADY_CLOSED", "La sesion de caja ya estaba cerrada")

      {:error, changeset} ->
        error(conn, :unprocessable_entity, "VALIDATION_ERROR", inspect(changeset.errors))
    end
  end

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{code: code, message: message})
  end
end
