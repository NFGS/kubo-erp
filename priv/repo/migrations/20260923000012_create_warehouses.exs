defmodule KuboErp.Repo.Migrations.CreateWarehouses do
  use Ecto.Migration

  @moduledoc """
  Stock por bodega y transferencias (P-22, ADR-0016).

  `stock_levels` pasa a ser la fuente de verdad por bodega; `products.stock`
  queda como total denormalizado (lo mantiene la misma transaccion) para que las
  lecturas existentes —POS, reportes, tablero— no cambien. El kardex gana la
  bodega y su indice de idempotencia la incluye: una transferencia mueve el
  mismo producto dos veces con la misma referencia.

  El backfill corre ANTES de activar RLS: sin contexto de negocio las politicas
  no dejarian insertar las filas historicas.
  """

  @tenant "NULLIF(current_setting('app.tenant_id', true), '')::uuid"

  def up do
    create table(:warehouses, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, :binary_id, null: false)
      add(:name, :string, size: 120, null: false)
      add(:address, :string, size: 200)
      add(:is_default, :boolean, null: false, default: false)
      add(:active, :boolean, null: false, default: true)
      add(:deleted_at, :utc_datetime)

      timestamps(type: :utc_datetime)
    end

    create(index(:warehouses, [:tenant_id]))

    # Una sola bodega por defecto por negocio, garantizada por el motor.
    create(
      unique_index(:warehouses, [:tenant_id, :is_default],
        where: "is_default AND deleted_at IS NULL",
        name: :warehouses_tenant_default_unique
      )
    )

    create table(:stock_levels, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, :binary_id, null: false)

      add(:warehouse_id, references(:warehouses, type: :binary_id, on_delete: :restrict),
        null: false
      )

      add(:product_id, references(:products, type: :binary_id, on_delete: :restrict), null: false)
      add(:stock, :integer, null: false, default: 0)

      timestamps(type: :utc_datetime)
    end

    create(
      unique_index(:stock_levels, [:tenant_id, :warehouse_id, :product_id],
        name: :stock_levels_warehouse_product_unique
      )
    )

    create(index(:stock_levels, [:tenant_id, :product_id]))

    create table(:stock_transfers, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, :binary_id, null: false)

      add(:from_warehouse_id, references(:warehouses, type: :binary_id, on_delete: :restrict),
        null: false
      )

      add(:to_warehouse_id, references(:warehouses, type: :binary_id, on_delete: :restrict),
        null: false
      )

      add(:status, :string, size: 20, null: false, default: "COMPLETED")
      add(:notes, :string, size: 200)
      add(:created_by, :binary_id)
      add(:completed_at, :utc_datetime)

      timestamps(type: :utc_datetime)
    end

    create(index(:stock_transfers, [:tenant_id, :inserted_at]))

    create table(:stock_transfer_items, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, :binary_id, null: false)

      add(:transfer_id, references(:stock_transfers, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:product_id, references(:products, type: :binary_id, on_delete: :restrict), null: false)
      add(:quantity, :integer, null: false)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create(index(:stock_transfer_items, [:tenant_id, :transfer_id]))

    create(
      constraint(:stock_transfer_items, :stock_transfer_items_quantity_positive,
        check: "quantity > 0"
      )
    )

    alter table(:stock_movements) do
      add(:warehouse_id, :binary_id)
    end

    drop(
      unique_index(:stock_movements, [:reference_type, :reference_id, :product_id],
        name: :stock_movements_reference_unique
      )
    )

    create(
      unique_index(
        :stock_movements,
        [:reference_type, :reference_id, :product_id, :warehouse_id],
        where: "reference_id IS NOT NULL",
        name: :stock_movements_reference_unique
      )
    )

    # --- Backfill: bodega por defecto, niveles y kardex historico ---------------
    execute("""
    INSERT INTO warehouses (id, tenant_id, name, is_default, active, inserted_at, updated_at)
    SELECT gen_random_uuid(), negocios.tenant_id, 'Bodega principal', true, true, now(), now()
    FROM (
      SELECT DISTINCT tenant_id FROM products
      UNION
      SELECT DISTINCT tenant_id FROM stock_movements
    ) AS negocios
    """)

    execute("""
    UPDATE stock_movements AS m
    SET warehouse_id = w.id
    FROM warehouses AS w
    WHERE w.tenant_id = m.tenant_id AND w.is_default
    """)

    execute("ALTER TABLE stock_movements ALTER COLUMN warehouse_id SET NOT NULL")

    execute("""
    INSERT INTO stock_levels (id, tenant_id, warehouse_id, product_id, stock, inserted_at, updated_at)
    SELECT gen_random_uuid(), p.tenant_id, w.id, p.id, p.stock, now(), now()
    FROM products AS p
    JOIN warehouses AS w ON w.tenant_id = p.tenant_id AND w.is_default
    """)

    # --- RLS despues del backfill ----------------------------------------------
    for tabla <- ["warehouses", "stock_levels", "stock_transfers", "stock_transfer_items"] do
      execute("ALTER TABLE #{tabla} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{tabla} FORCE ROW LEVEL SECURITY")
      execute("DROP POLICY IF EXISTS #{tabla}_tenant_isolation ON #{tabla}")

      execute("""
      CREATE POLICY #{tabla}_tenant_isolation ON #{tabla}
        USING (tenant_id = #{@tenant})
        WITH CHECK (tenant_id = #{@tenant})
      """)
    end
  end

  def down do
    for tabla <- ["stock_transfer_items", "stock_transfers", "stock_levels", "warehouses"] do
      execute("DROP POLICY IF EXISTS #{tabla}_tenant_isolation ON #{tabla}")
      execute("ALTER TABLE #{tabla} NO FORCE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{tabla} DISABLE ROW LEVEL SECURITY")
    end

    drop(
      unique_index(:stock_movements, [:reference_type, :reference_id, :product_id, :warehouse_id],
        name: :stock_movements_reference_unique
      )
    )

    alter table(:stock_movements) do
      remove(:warehouse_id)
    end

    create(
      unique_index(:stock_movements, [:reference_type, :reference_id, :product_id],
        where: "reference_id IS NOT NULL",
        name: :stock_movements_reference_unique
      )
    )

    drop(table(:stock_transfer_items))
    drop(table(:stock_transfers))
    drop(table(:stock_levels))
    drop(table(:warehouses))
  end
end
