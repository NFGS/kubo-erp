defmodule KuboErp.Catalog do
  @moduledoc """
  Catalogo de productos e inventario (kardex).

  `products.stock` es una proyeccion para lecturas rapidas; la fuente de verdad
  son los movimientos de `stock_movements`.
  """

  import Ecto.Query

  alias KuboErp.{Pagination, Repo}
  alias KuboErp.Catalog.{Product, StockMovement}

  # ---------------------------------------------------------------------------
  # Consultas
  # ---------------------------------------------------------------------------

  def list_products(tenant_id, filters \\ %{}) do
    {limit, offset} = Pagination.normalize(filters)

    tenant_id
    |> products_query(filters)
    |> order_by([p], asc: p.name)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc "Total real de productos que cumplen el filtro (para paginar en la interfaz)."
  def count_products(tenant_id, filters \\ %{}) do
    tenant_id |> products_query(filters) |> Repo.aggregate(:count)
  end

  defp products_query(tenant_id, filters) do
    Product
    |> where([p], p.tenant_id == ^tenant_id and is_nil(p.deleted_at))
    |> filter_by_query(filters["q"])
    |> filter_low_stock(filters["low_stock"])
  end

  def get_product(_tenant_id, nil), do: nil

  def get_product(tenant_id, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id) do
      Product
      |> where([p], p.tenant_id == ^tenant_id and p.id == ^uuid and is_nil(p.deleted_at))
      |> Repo.one()
    else
      :error -> nil
    end
  end

  def stats(tenant_id) do
    base = from(p in Product, where: p.tenant_id == ^tenant_id and is_nil(p.deleted_at))

    %{
      total: Repo.aggregate(base, :count),
      active: Repo.aggregate(from(p in base, where: p.active), :count),
      low_stock: Repo.aggregate(from(p in base, where: p.stock <= p.min_stock), :count),
      inventory_value:
        Repo.one(
          from(p in base,
            select: coalesce(sum(fragment("? * ?", p.stock, p.cost)), 0)
          )
        )
        |> to_decimal()
    }
  end

  def list_movements(tenant_id, product_id \\ nil, opts \\ []) do
    {limit, offset} = Pagination.normalize(opts)

    tenant_id
    |> movements_query(product_id)
    |> order_by([m], desc: m.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc "Total real de movimientos del kardex que cumplen el filtro."
  def count_movements(tenant_id, product_id \\ nil) do
    tenant_id |> movements_query(product_id) |> Repo.aggregate(:count)
  end

  defp movements_query(tenant_id, product_id) do
    StockMovement
    |> where([m], m.tenant_id == ^tenant_id)
    |> filter_product(product_id)
  end

  # ---------------------------------------------------------------------------
  # Comandos
  # ---------------------------------------------------------------------------

  def create_product(tenant_id, attrs) do
    %Product{tenant_id: tenant_id}
    |> Product.changeset(attrs)
    |> Repo.insert()
  end

  def update_product(product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
  end

  def soft_delete(product) do
    product
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  @doc """
  Ajuste manual de inventario. `kind` es `IN` (entrada), `OUT` (salida) o
  `ADJUST` (fijar el stock en un valor absoluto).
  """
  def adjust_stock(tenant_id, user_id, product_id, attrs) do
    with {:ok, uuid} <- cast_uuid(product_id),
         {:ok, quantity} <- parse_quantity(attrs["quantity"]),
         kind when kind in ["IN", "OUT", "ADJUST"] <- attrs["kind"] do
      case Repo.scoped_transaction(fn ->
             case lock_product(tenant_id, uuid) do
               nil ->
                 Repo.rollback(:product_not_found)

               product ->
                 delta =
                   case kind do
                     "IN" -> quantity
                     "OUT" -> -quantity
                     "ADJUST" -> quantity - product.stock
                   end

                 case move_stock(product, delta,
                        kind: kind,
                        reason: attrs["reason"] || "Ajuste manual",
                        reference_type: "MANUAL",
                        created_by: user_id
                      ) do
                   {:ok, updated, movement} -> {updated, movement}
                   {:error, reason} -> Repo.rollback(reason)
                 end
             end
           end) do
        {:ok, {product, movement}} -> {:ok, product, movement}
        {:error, reason} -> {:error, reason}
      end
    else
      :error -> {:error, :invalid_product_id}
      {:error, reason} -> {:error, reason}
      _kind -> {:error, :invalid_kind}
    end
  end

  @doc """
  Mueve el inventario de un producto bloqueado y registra el movimiento.

  Debe invocarse SIEMPRE dentro de una transaccion y con el producto obtenido
  mediante `lock_product/2` (bloqueo `FOR UPDATE`), para que dos ventas
  simultaneas no vendan el mismo stock.
  """
  def move_stock(product, delta, opts) do
    new_stock = product.stock + delta

    if new_stock < 0 do
      {:error, {:insufficient_stock, product}}
    else
      with {:ok, updated} <-
             product
             |> Ecto.Changeset.change(stock: new_stock)
             |> Repo.update(),
           {:ok, movement} <- insert_movement(updated, delta, new_stock, opts) do
        {:ok, updated, movement}
      else
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  @doc "Obtiene y bloquea el producto para actualizar su stock sin carreras."
  def lock_product(tenant_id, product_id) do
    Product
    |> where([p], p.tenant_id == ^tenant_id and p.id == ^product_id and is_nil(p.deleted_at))
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  # ---------------------------------------------------------------------------
  # Internos
  # ---------------------------------------------------------------------------

  defp insert_movement(product, delta, stock_after, opts) do
    %StockMovement{}
    |> StockMovement.changeset(%{
      tenant_id: product.tenant_id,
      product_id: product.id,
      kind: opts[:kind] || if(delta >= 0, do: "IN", else: "OUT"),
      quantity: abs(delta),
      stock_after: stock_after,
      reason: opts[:reason],
      reference_type: opts[:reference_type],
      reference_id: opts[:reference_id],
      created_by: opts[:created_by]
    })
    |> Repo.insert()
  end

  defp filter_by_query(query, term) when is_binary(term) and term != "" do
    sanitized = String.replace(term, ["%", "_", "\\"], "")
    like = "%" <> sanitized <> "%"
    from(p in query, where: ilike(p.name, ^like) or ilike(p.sku, ^like))
  end

  defp filter_by_query(query, _term), do: query

  defp filter_low_stock(query, "true"), do: from(p in query, where: p.stock <= p.min_stock)
  defp filter_low_stock(query, _value), do: query

  defp filter_product(query, nil), do: query

  defp filter_product(query, product_id) do
    case cast_uuid(product_id) do
      {:ok, uuid} -> from(m in query, where: m.product_id == ^uuid)
      :error -> from(m in query, where: false)
    end
  end

  defp cast_uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> :error
    end
  end

  defp cast_uuid(_value), do: :error

  defp parse_quantity(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_quantity(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> {:error, :invalid_quantity}
    end
  end

  defp parse_quantity(_value), do: {:error, :invalid_quantity}

  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value), do: Decimal.new(to_string(value))
end
