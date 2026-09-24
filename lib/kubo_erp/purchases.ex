defmodule KuboErp.Purchases do
  @moduledoc """
  Registro de compras (P-15).

  Una compra es una operacion **transaccional**: bloquea los productos,
  inserta la compra y su detalle, **suma** el inventario, registra el kardex
  (`reference_type = PURCHASE`), actualiza el costo del producto con el valor
  sin IVA y deja el evento `purchase.received` en la bandeja de salida. Anular
  la compra revierte el stock (`PURCHASE_VOID`) sin borrar la historia.

  El costo unitario se interpreta **con IVA incluido** (misma convencion que el
  precio de venta del catalogo); el costo del producto se guarda sin IVA, que es
  lo que sirve para calcular margen.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias KuboErp.{Catalog, Pagination, Repo, Sales}
  alias KuboErp.Catalog.Product
  alias KuboErp.Purchasing.{Purchase, PurchaseItem, Supplier}
  alias KuboErp.Events.{Outbox, Publisher, PurchaseReceived}

  @default_tax_rate Decimal.new("19.00")

  # ---------------------------------------------------------------------------
  # Consultas
  # ---------------------------------------------------------------------------

  def list(tenant_id, opts \\ []) do
    {limit, offset} = Pagination.normalize(opts)

    tenant_id
    |> base(opts[:status], opts[:supplier_id])
    |> order_by([p], desc: p.received_at)
    |> limit(^limit)
    |> offset(^offset)
    |> preload(:items)
    |> Repo.all()
  end

  def count(tenant_id, opts \\ []) do
    tenant_id |> base(opts[:status], opts[:supplier_id]) |> Repo.aggregate(:count)
  end

  defp base(tenant_id, status, supplier_id) do
    Purchase
    |> where([p], p.tenant_id == ^tenant_id)
    |> filter_status(status)
    |> filter_supplier(supplier_id)
  end

  def get(_tenant_id, nil), do: nil

  def get(tenant_id, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id) do
      Purchase
      |> where([p], p.tenant_id == ^tenant_id and p.id == ^uuid)
      |> preload(:items)
      |> Repo.one()
    else
      :error -> nil
    end
  end

  def stats(tenant_id) do
    received =
      from(p in Purchase, where: p.tenant_id == ^tenant_id and p.status == "RECEIVED")

    suppliers =
      from(s in Supplier, where: s.tenant_id == ^tenant_id and is_nil(s.deleted_at))

    %{
      purchases_count: Repo.aggregate(received, :count),
      total_purchased:
        Repo.one(from(p in received, select: coalesce(sum(p.total), 0))) |> to_decimal(),
      suppliers_count: Repo.aggregate(suppliers, :count)
    }
  end

  # ---------------------------------------------------------------------------
  # Comandos
  # ---------------------------------------------------------------------------

  def create(tenant_id, user_id, attrs) do
    items = normalize_items(attrs["items"] || attrs[:items])

    if items == [] do
      {:error, :empty_items}
    else
      case Repo.transaction(fn -> insert_purchase(tenant_id, user_id, attrs, items) end) do
        {:ok, {purchase, purchase_items}} ->
          Publisher.kick()
          {:ok, %{purchase | items: purchase_items}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def void(tenant_id, user_id, id) do
    case get(tenant_id, id) do
      nil ->
        {:error, :not_found}

      %Purchase{status: "VOIDED"} ->
        {:error, :already_voided}

      %Purchase{} = purchase ->
        Repo.transaction(fn ->
          products = lock_products(tenant_id, Enum.map(purchase.items, & &1.product_id))

          Enum.each(purchase.items, fn item ->
            case Map.get(products, item.product_id) do
              nil ->
                :ok

              product ->
                case Catalog.move_stock(product, -item.quantity,
                       kind: "OUT",
                       reason: "Anulacion de la compra #{purchase.number}",
                       reference_type: "PURCHASE_VOID",
                       reference_id: purchase.id,
                       created_by: user_id
                     ) do
                  {:ok, _product, _movement} -> :ok
                  {:error, reason} -> Repo.rollback(reason)
                end
            end
          end)

          purchase
          |> Changeset.change(
            status: "VOIDED",
            voided_at: DateTime.utc_now() |> DateTime.truncate(:second)
          )
          |> Repo.update!()
        end)
    end
  end

  # ---------------------------------------------------------------------------
  # Internos
  # ---------------------------------------------------------------------------

  defp insert_purchase(tenant_id, user_id, attrs, items) do
    supplier = fetch_supplier(tenant_id, attrs["supplier_id"])
    products = lock_products(tenant_id, Enum.map(items, & &1.product_id))

    prepared =
      Enum.map(items, fn item ->
        case Map.get(products, item.product_id) do
          nil ->
            Repo.rollback(:product_not_found)

          product ->
            tax_rate = item.tax_rate || product.tax_rate || @default_tax_rate
            amounts = Sales.line_amounts(item.quantity, item.unit_cost, tax_rate)
            {product, item, tax_rate, amounts}
        end
      end)

    totals = Sales.totals(Enum.map(prepared, fn {_product, _item, _rate, amounts} -> amounts end))

    purchase =
      insert_purchase_record(%{
        tenant_id: tenant_id,
        number: next_number(tenant_id),
        supplier_id: supplier.id,
        supplier_name: supplier.name,
        status: "RECEIVED",
        subtotal: totals.subtotal,
        tax: totals.tax,
        total: totals.total,
        notes: attrs["notes"],
        received_by: user_id,
        received_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    purchase_items =
      Enum.map(prepared, fn {product, item, tax_rate, amounts} ->
        insert_item_and_receive_stock(purchase, product, item, tax_rate, amounts, user_id)
      end)

    Outbox.enqueue(PurchaseReceived.build(purchase, purchase_items))

    {purchase, purchase_items}
  end

  defp fetch_supplier(tenant_id, raw_id) do
    with {:ok, uuid} <- cast_uuid(raw_id) do
      case Supplier
           |> where([s], s.tenant_id == ^tenant_id and s.id == ^uuid and is_nil(s.deleted_at))
           |> Repo.one() do
        nil -> Repo.rollback(:supplier_not_found)
        supplier -> supplier
      end
    else
      :error -> Repo.rollback(:supplier_not_found)
    end
  end

  defp insert_purchase_record(attrs) do
    case %Purchase{} |> Purchase.changeset(attrs) |> Repo.insert() do
      {:ok, purchase} -> purchase
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp insert_item_and_receive_stock(purchase, product, item, tax_rate, amounts, user_id) do
    unit_cost = item.unit_cost || product.cost || Decimal.new(0)

    purchase_item =
      case %PurchaseItem{}
           |> PurchaseItem.changeset(%{
             purchase_id: purchase.id,
             tenant_id: purchase.tenant_id,
             product_id: product.id,
             product_name: product.name,
             quantity: item.quantity,
             unit_cost: unit_cost,
             tax_rate: tax_rate,
             tax_amount: amounts.tax,
             total: amounts.total
           })
           |> Repo.insert() do
        {:ok, inserted} -> inserted
        {:error, changeset} -> Repo.rollback(changeset)
      end

    case Catalog.move_stock(product, item.quantity,
           kind: "IN",
           reason: "Compra #{purchase.number}",
           reference_type: "PURCHASE",
           reference_id: purchase.id,
           created_by: user_id
         ) do
      {:ok, updated, _movement} ->
        update_cost(updated, amounts.subtotal, item.quantity)
        purchase_item

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  # El costo del producto queda sin IVA: es el valor con el que se calcula margen.
  defp update_cost(product, subtotal, quantity) do
    unit_cost =
      subtotal
      |> Decimal.div(Decimal.new(quantity))
      |> Decimal.round(2)

    case product |> Changeset.change(cost: unit_cost) |> Repo.update() do
      {:ok, _product} -> :ok
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp lock_products(tenant_id, product_ids) do
    ids = product_ids |> Enum.uniq() |> Enum.reject(&is_nil/1)

    Product
    |> where([p], p.tenant_id == ^tenant_id and p.id in ^ids and is_nil(p.deleted_at))
    |> lock("FOR UPDATE")
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  # Siguiente numero de compra del negocio.
  #
  # Usa el contador atomico `tenant_counters.purchase_seq` (misma leccion que la
  # numeracion de ventas): un UPSERT devuelve el consecutivo sin conflictos.
  defp next_number(tenant_id) do
    %{rows: [[sequence]]} =
      Repo.query!(
        """
        INSERT INTO tenant_counters (tenant_id, purchase_seq)
        VALUES ($1, 1)
        ON CONFLICT (tenant_id)
        DO UPDATE SET purchase_seq = tenant_counters.purchase_seq + 1
        RETURNING purchase_seq
        """,
        [Ecto.UUID.dump!(tenant_id)]
      )

    "C-" <> String.pad_leading(Integer.to_string(sequence), 6, "0")
  end

  defp normalize_items(items) when is_list(items) do
    items |> Enum.map(&normalize_item/1) |> Enum.reject(&is_nil/1)
  end

  defp normalize_items(_items), do: []

  defp normalize_item(%{"product_id" => product_id, "quantity" => quantity} = item) do
    with {:ok, uuid} <- cast_uuid(product_id),
         {:ok, parsed_quantity} <- parse_quantity(quantity) do
      %{
        product_id: uuid,
        quantity: parsed_quantity,
        unit_cost: parse_decimal(item["unit_cost"]),
        tax_rate: parse_decimal(item["tax_rate"])
      }
    else
      _ -> nil
    end
  end

  defp normalize_item(_item), do: nil

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

  defp parse_decimal(nil), do: nil

  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end

  defp parse_decimal(%Decimal{} = value), do: value
  defp parse_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp parse_decimal(_value), do: nil

  defp filter_status(query, nil), do: query
  defp filter_status(query, status), do: from(p in query, where: p.status == ^status)

  defp filter_supplier(query, nil), do: query

  defp filter_supplier(query, supplier_id) do
    case cast_uuid(supplier_id) do
      {:ok, uuid} -> from(p in query, where: p.supplier_id == ^uuid)
      :error -> from(p in query, where: false)
    end
  end

  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value), do: Decimal.new(to_string(value))
end
