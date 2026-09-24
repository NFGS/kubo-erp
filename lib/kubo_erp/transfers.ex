defmodule KuboErp.Transfers do
  @moduledoc """
  Transferencias entre bodegas (P-22, ADR-0016).

  Una transferencia completada es un **par de movimientos atomicos**: sale del
  origen y entra en el destino en la misma transaccion, con la misma referencia
  (`TRANSFER` + id de la transferencia). Si falta existencia en el origen no se
  mueve nada.
  """

  import Ecto.Query

  alias KuboErp.{Catalog, Repo, Warehouses}
  alias KuboErp.Transfers.{StockTransfer, StockTransferItem}

  def list(tenant_id, limit \\ 50) do
    StockTransfer
    |> where([t], t.tenant_id == ^tenant_id)
    |> order_by([t], desc: t.inserted_at)
    |> limit(^limit)
    |> preload(:items)
    |> Repo.all()
  end

  def get(tenant_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        StockTransfer
        |> where([t], t.tenant_id == ^tenant_id and t.id == ^uuid)
        |> preload(:items)
        |> Repo.one()

      :error ->
        nil
    end
  end

  @doc "Transfiere existencias entre dos bodegas del negocio."
  def create(tenant_id, user_id, attrs) do
    items = normalize_items(attrs["items"] || attrs[:items])

    with :ok <- validar(tenant_id, attrs["from_warehouse_id"], attrs["to_warehouse_id"], items) do
      Repo.scoped_transaction(fn ->
        {:ok, transferencia} =
          %StockTransfer{}
          |> StockTransfer.changeset(%{
            tenant_id: tenant_id,
            from_warehouse_id: attrs["from_warehouse_id"],
            to_warehouse_id: attrs["to_warehouse_id"],
            status: "COMPLETED",
            notes: attrs["notes"],
            created_by: user_id,
            completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })
          |> Repo.insert()

        Enum.each(items, fn item ->
          mover_item(transferencia, item, user_id)
        end)

        # La transaccion devuelve la transferencia; `Repo.transaction` la envuelve.
        %{transferencia | items: insertar_items(transferencia, items)}
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Internos
  # ---------------------------------------------------------------------------

  defp mover_item(transferencia, item, user_id) do
    product =
      case Catalog.lock_product(transferencia.tenant_id, item.product_id) do
        nil -> Repo.rollback(:product_not_found)
        producto -> producto
      end

    # Un servicio no tiene inventario que trasladar (P-17).
    if not product.tracks_stock do
      Repo.rollback(:product_without_stock)
    end

    referencia = [
      kind: nil,
      reason: "Transferencia entre bodegas",
      reference_type: "TRANSFER",
      reference_id: transferencia.id,
      created_by: user_id
    ]

    # La segunda pata usa el producto DEVUELTO por la primera: el struct
    # original quedo con el stock viejo y sumarle el ingreso inflaria el total.
    with {:ok, tras_salida, _salida} <-
           Catalog.move_stock(
             product,
             -item.quantity,
             Keyword.merge(referencia,
               kind: "OUT",
               warehouse_id: transferencia.from_warehouse_id
             )
           ),
         {:ok, _producto, _entrada} <-
           Catalog.move_stock(
             tras_salida,
             item.quantity,
             Keyword.merge(referencia,
               kind: "IN",
               warehouse_id: transferencia.to_warehouse_id
             )
           ) do
      :ok
    else
      {:error, razon} -> Repo.rollback(razon)
    end
  end

  defp insertar_items(transferencia, items) do
    Enum.map(items, fn item ->
      %StockTransferItem{}
      |> StockTransferItem.changeset(%{
        tenant_id: transferencia.tenant_id,
        transfer_id: transferencia.id,
        product_id: item.product_id,
        quantity: item.quantity
      })
      |> Repo.insert!()
    end)
  end

  defp validar(tenant_id, from_id, to_id, items) do
    cond do
      items == [] -> {:error, :empty_items}
      from_id == to_id -> {:error, :same_warehouse}
      is_nil(Warehouses.get(tenant_id, from_id)) -> {:error, :origin_not_found}
      is_nil(Warehouses.get(tenant_id, to_id)) -> {:error, :destination_not_found}
      true -> :ok
    end
  end

  defp normalize_items(items) when is_list(items) do
    items
    |> Enum.map(&normalize_item/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_items(_items), do: []

  defp normalize_item(%{"product_id" => product_id, "quantity" => quantity}) do
    with {:ok, uuid} <- Ecto.UUID.cast(product_id),
         {:ok, parsed} <- parse_quantity(quantity) do
      %{product_id: uuid, quantity: parsed}
    else
      _ -> nil
    end
  end

  defp normalize_item(_item), do: nil

  defp parse_quantity(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_quantity(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> {:error, :invalid_quantity}
    end
  end

  defp parse_quantity(_value), do: {:error, :invalid_quantity}
end
