defmodule KuboErp.Sales do
  @moduledoc """
  Registro de ventas.

  La venta es una operacion **transaccional** que: bloquea los productos
  implicados, valida existencias, inserta la venta y su detalle, descuenta el
  inventario, deja el rastro en el kardex y guarda el evento `sale.created` en
  la bandeja de salida. Venta y evento se confirman juntos: si la transaccion
  se revierte, no queda un evento de algo que no ocurrio, y si se confirma, el
  evento se entregara aunque el bus este caido (patron *transactional outbox*).
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias KuboErp.{Cash, Catalog, Pagination, Repo}
  alias KuboErp.Catalog.Product
  alias KuboErp.Sales.{Sale, SaleItem}
  alias KuboErp.Events.{Outbox, Publisher, SaleCreated}

  @default_tax_rate Decimal.new("19.00")
  @number_retries 3

  # ---------------------------------------------------------------------------
  # Consultas
  # ---------------------------------------------------------------------------

  def list_sales(tenant_id, opts \\ []) do
    {limit, offset} = Pagination.normalize(opts)

    tenant_id
    |> sales_query(opts[:status])
    |> order_by([s], desc: s.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> preload(:items)
    |> Repo.all()
  end

  @doc "Total real de ventas que cumplen el filtro (para paginar en la interfaz)."
  def count_sales(tenant_id, status \\ nil) do
    tenant_id |> sales_query(status) |> Repo.aggregate(:count)
  end

  defp sales_query(tenant_id, status) do
    Sale
    |> where([s], s.tenant_id == ^tenant_id)
    |> filter_status(status)
  end

  def get_sale(_tenant_id, nil), do: nil

  def get_sale(tenant_id, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id) do
      Sale
      |> where([s], s.tenant_id == ^tenant_id and s.id == ^uuid)
      |> preload(:items)
      |> Repo.one()
    else
      :error -> nil
    end
  end

  def stats(tenant_id) do
    timezone = business_timezone()
    today = business_today(timezone)

    completed =
      from(s in Sale, where: s.tenant_id == ^tenant_id and s.status == "COMPLETED")

    %{
      sales_count: Repo.aggregate(completed, :count),
      total_sold:
        Repo.one(from(s in completed, select: coalesce(sum(s.total), 0))) |> to_decimal(),
      sales_today:
        Repo.one(
          from(s in completed,
            where:
              fragment(
                "(? AT TIME ZONE 'UTC' AT TIME ZONE ?)::date = ?",
                s.inserted_at,
                ^timezone,
                ^today
              ),
            select: coalesce(sum(s.total), 0)
          )
        )
        |> to_decimal(),
      sales_today_count:
        Repo.aggregate(
          from(s in completed,
            where:
              fragment(
                "(? AT TIME ZONE 'UTC' AT TIME ZONE ?)::date = ?",
                s.inserted_at,
                ^timezone,
                ^today
              )
          ),
          :count
        ),
      timezone: timezone,
      business_date: Date.to_iso8601(today),
      voided_count:
        Repo.aggregate(
          from(s in Sale, where: s.tenant_id == ^tenant_id and s.status == "VOIDED"),
          :count
        )
    }
  end

  @doc """
  Zona horaria del negocio, configurable con `KUBO_TIMEZONE`.

  Las columnas de fecha se guardan en UTC (correcto para almacenar), pero el dia
  comercial se calcula en la zona del negocio: una venta de las 20:00 en Colombia
  pertenece a ese dia, no al siguiente.
  """
  def business_timezone do
    Application.get_env(:kubo_erp, :timezone, "America/Bogota")
  end

  defp business_today(timezone) do
    case DateTime.now(timezone) do
      {:ok, now} -> DateTime.to_date(now)
      _error -> Date.utc_today()
    end
  end

  # ---------------------------------------------------------------------------
  # Calculo de importes (funciones puras, sin base de datos)
  # ---------------------------------------------------------------------------

  @doc """
  Desagrega un importe con IVA incluido (precio final al publico).

      iex> line_amounts(2, Decimal.new("11900.00"), Decimal.new("19.00"))
      %{
        total: Decimal.new("23800.00"),
        tax: Decimal.new("3800.00"),
        subtotal: Decimal.new("20000.00")
      }
  """
  def line_amounts(quantity, unit_price, tax_rate) do
    total = unit_price |> Decimal.mult(Decimal.new(quantity)) |> Decimal.round(2)
    divisor = Decimal.add(Decimal.new(100), tax_rate)
    tax = total |> Decimal.mult(tax_rate) |> Decimal.div(divisor) |> Decimal.round(2)

    %{total: total, tax: tax, subtotal: Decimal.sub(total, tax)}
  end

  @doc "Suma los importes de todas las lineas."
  def totals(line_amounts) do
    Enum.reduce(
      line_amounts,
      %{subtotal: Decimal.new(0), tax: Decimal.new(0), total: Decimal.new(0)},
      fn amounts, acc ->
        %{
          subtotal: Decimal.add(acc.subtotal, amounts.subtotal),
          tax: Decimal.add(acc.tax, amounts.tax),
          total: Decimal.add(acc.total, amounts.total)
        }
      end
    )
  end

  # ---------------------------------------------------------------------------
  # Comandos
  # ---------------------------------------------------------------------------

  def create_sale(tenant_id, user_id, attrs) do
    items = normalize_items(attrs["items"] || attrs[:items])

    if items == [] do
      {:error, :empty_items}
    else
      do_create_sale(tenant_id, user_id, attrs, items, 0)
    end
  end

  def void_sale(tenant_id, user_id, id) do
    case get_sale(tenant_id, id) do
      nil ->
        {:error, :not_found}

      %Sale{status: "VOIDED"} ->
        {:error, :already_voided}

      %Sale{} = sale ->
        Repo.scoped_transaction(fn ->
          products = lock_products(tenant_id, Enum.map(sale.items, & &1.product_id))

          Enum.each(sale.items, fn item ->
            case Map.get(products, item.product_id) do
              nil ->
                :ok

              product ->
                case Catalog.move_stock(product, item.quantity,
                       kind: "IN",
                       reason: "Anulacion de la venta #{sale.number}",
                       reference_type: "VOID",
                       reference_id: sale.id,
                       created_by: user_id
                     ) do
                  {:ok, _product, _movement} -> :ok
                  {:error, reason} -> Repo.rollback(reason)
                end
            end
          end)

          sale
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

  defp do_create_sale(tenant_id, user_id, attrs, items, attempt) do
    case Repo.scoped_transaction(fn -> insert_sale(tenant_id, user_id, attrs, items) end) do
      {:ok, {sale, sale_items}} ->
        Publisher.kick()
        {:ok, %{sale | items: sale_items}}

      {:error, :number_conflict} when attempt < @number_retries ->
        do_create_sale(tenant_id, user_id, attrs, items, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp insert_sale(tenant_id, user_id, attrs, items) do
    products = lock_products(tenant_id, Enum.map(items, & &1.product_id))

    prepared =
      Enum.map(items, fn item ->
        case Map.get(products, item.product_id) do
          nil ->
            Repo.rollback(:product_not_found)

          product ->
            if product.stock < item.quantity do
              Repo.rollback({:insufficient_stock, product})
            end

            tax_rate = item.tax_rate || product.tax_rate || @default_tax_rate
            amounts = line_amounts(item.quantity, product.price, tax_rate)
            {product, item, tax_rate, amounts}
        end
      end)

    totals = totals(Enum.map(prepared, fn {_product, _item, _rate, amounts} -> amounts end))

    sale =
      insert_sale_record(%{
        tenant_id: tenant_id,
        customer_id: cast_uuid(attrs["customer_id"]),
        customer_name: attrs["customer_name"],
        payment_method: attrs["payment_method"] || "CASH",
        status: "COMPLETED",
        subtotal: totals.subtotal,
        tax: totals.tax,
        total: totals.total,
        notes: attrs["notes"],
        sold_by: user_id,
        # La venta se liga al turno de caja abierto: el arqueo suma exactamente
        # las ventas de la sesion (P-16).
        cash_session_id: Cash.open_session_id(tenant_id)
      })

    sale_items =
      Enum.map(prepared, fn {product, item, tax_rate, amounts} ->
        insert_item_and_move_stock(sale, product, item, tax_rate, amounts, user_id)
      end)

    # El evento entra en la MISMA transaccion de la venta (outbox). Si algo
    # revierte, el evento desaparece con ella; si confirma, ya no se pierde.
    Outbox.enqueue(SaleCreated.build(sale, sale_items))

    {sale, sale_items}
  end

  defp insert_sale_record(attrs) do
    changeset =
      %Sale{}
      |> Sale.changeset(Map.put(attrs, :number, next_number(attrs.tenant_id)))

    case Repo.insert(changeset) do
      {:ok, sale} -> sale
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp insert_item_and_move_stock(sale, product, item, tax_rate, amounts, user_id) do
    sale_item =
      case %SaleItem{}
           |> SaleItem.changeset(%{
             sale_id: sale.id,
             tenant_id: sale.tenant_id,
             product_id: product.id,
             product_name: product.name,
             quantity: item.quantity,
             unit_price: product.price,
             tax_rate: tax_rate,
             tax_amount: amounts.tax,
             total: amounts.total
           })
           |> Repo.insert() do
        {:ok, inserted} -> inserted
        {:error, changeset} -> Repo.rollback(changeset)
      end

    case Catalog.move_stock(product, -item.quantity,
           kind: "OUT",
           reason: "Venta #{sale.number}",
           reference_type: "SALE",
           reference_id: sale.id,
           created_by: user_id
         ) do
      {:ok, _product, _movement} -> sale_item
      {:error, reason} -> Repo.rollback(reason)
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

  @doc """
  Siguiente numero de venta del negocio.

  Se toma de `tenant_counters` con un UPSERT atomico: el contador se incrementa
  y devuelve en una sola sentencia, sin leer el maximo ni reintentar. La fila
  queda bloqueada hasta el final de la transaccion, de modo que dos cajas nunca
  obtienen el mismo numero. El indice unico `(tenant_id, number)` sigue ahi como
  red de seguridad.
  """
  defp next_number(tenant_id) do
    %{rows: [[sequence]]} =
      Repo.query!(
        """
        INSERT INTO tenant_counters (tenant_id, sale_seq)
        VALUES ($1, 1)
        ON CONFLICT (tenant_id)
        DO UPDATE SET sale_seq = tenant_counters.sale_seq + 1
        RETURNING sale_seq
        """,
        [Ecto.UUID.dump!(tenant_id)]
      )

    "V-" <> String.pad_leading(Integer.to_string(sequence), 6, "0")
  end

  defp normalize_items(items) when is_list(items) do
    items |> Enum.map(&normalize_item/1) |> Enum.reject(&is_nil/1)
  end

  defp normalize_items(_items), do: []

  defp normalize_item(%{"product_id" => product_id, "quantity" => quantity} = item) do
    with {:ok, uuid} <- cast_uuid_result(product_id),
         {:ok, parsed_quantity} <- parse_quantity(quantity) do
      %{
        product_id: uuid,
        quantity: parsed_quantity,
        tax_rate: parse_decimal(item["tax_rate"])
      }
    else
      _ -> nil
    end
  end

  defp normalize_item(_item), do: nil

  defp cast_uuid(value) do
    case cast_uuid_result(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  defp cast_uuid_result(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> :error
    end
  end

  defp cast_uuid_result(_value), do: :error

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
  defp parse_decimal(_value), do: nil

  defp filter_status(query, nil), do: query
  defp filter_status(query, status), do: from(s in query, where: s.status == ^status)

  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value), do: Decimal.new(to_string(value))
end
