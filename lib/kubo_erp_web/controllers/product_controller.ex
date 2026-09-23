defmodule KuboErpWeb.ProductController do
  @moduledoc "CRUD de productos del catalogo."

  use KuboErpWeb, :controller

  alias KuboErp.Catalog

  def index(conn, params) do
    products = Catalog.list_products(conn.assigns.tenant_id, params)
    render(conn, :index, products: products)
  end

  def stats(conn, _params) do
    render(conn, :stats, stats: Catalog.stats(conn.assigns.tenant_id))
  end

  def show(conn, %{"id" => id}) do
    case Catalog.get_product(conn.assigns.tenant_id, id) do
      nil -> not_found(conn)
      product -> render(conn, :show, product: product)
    end
  end

  def create(conn, params) do
    attrs = params["product"] || params

    case Catalog.create_product(conn.assigns.tenant_id, attrs) do
      {:ok, product} ->
        conn |> put_status(:created) |> render(:show, product: product)

      {:error, changeset} ->
        validation_error(conn, changeset)
    end
  end

  def update(conn, %{"id" => id} = params) do
    attrs = params["product"] || params

    case Catalog.get_product(conn.assigns.tenant_id, id) do
      nil ->
        not_found(conn)

      product ->
        case Catalog.update_product(product, attrs) do
          {:ok, updated} -> render(conn, :show, product: updated)
          {:error, changeset} -> validation_error(conn, changeset)
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case Catalog.get_product(conn.assigns.tenant_id, id) do
      nil ->
        not_found(conn)

      product ->
        {:ok, _} = Catalog.soft_delete(product)
        send_resp(conn, :no_content, "")
    end
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{code: "PRODUCT_NOT_FOUND", message: "El producto no existe"})
  end

  defp validation_error(conn, changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "VALIDATION_ERROR",
      message: errors_to_string(changeset),
      fields: Map.keys(changeset.errors)
    })
  end

  defp errors_to_string(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {message, _opts}} ->
      "#{field} #{message}"
    end)
  end
end
