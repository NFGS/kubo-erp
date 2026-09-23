defmodule KuboErp.Repo.Migrations.CreateErpSchema do
  use Ecto.Migration

  def change do
    create table(:products, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, :binary_id, null: false
      add :sku, :string, size: 60, null: false
      add :name, :string, size: 160, null: false
      add :description, :string, size: 400
      add :unit, :string, size: 10, null: false, default: "UN"
      add :price, :decimal, precision: 14, scale: 2, null: false, default: 0
      add :cost, :decimal, precision: 14, scale: 2, null: false, default: 0
      add :tax_rate, :decimal, precision: 5, scale: 2, null: false, default: 19.00
      add :stock, :integer, null: false, default: 0
      add :min_stock, :integer, null: false, default: 0
      add :active, :boolean, null: false, default: true
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:products, [:tenant_id, :sku],
             where: "deleted_at IS NULL",
             name: :products_tenant_sku_unique
           )

    create index(:products, [:tenant_id, :active])
    create constraint(:products, :products_stock_not_negative, check: "stock >= 0")

    create table(:stock_movements, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, :binary_id, null: false
      add :product_id, references(:products, type: :binary_id, on_delete: :restrict), null: false
      add :kind, :string, size: 10, null: false
      add :quantity, :integer, null: false
      add :stock_after, :integer, null: false
      add :reason, :string, size: 200
      add :reference_type, :string, size: 20
      add :reference_id, :binary_id
      add :created_by, :binary_id

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:stock_movements, [:tenant_id, :product_id, :inserted_at])

    # Idempotencia: una venta (o su anulacion) no puede mover dos veces el mismo producto.
    create unique_index(:stock_movements, [:reference_type, :reference_id, :product_id],
             where: "reference_id IS NOT NULL",
             name: :stock_movements_reference_unique
           )

    create constraint(:stock_movements, :stock_movements_quantity_positive, check: "quantity > 0")

    create table(:sales, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, :binary_id, null: false
      add :number, :string, size: 20, null: false

      # Referencia al cliente del CRM por identificador (sin llave foranea entre
      # servicios) + copia del nombre para no depender de otro servicio al leer.
      add :customer_id, :binary_id
      add :customer_name, :string, size: 160

      add :status, :string, size: 20, null: false, default: "COMPLETED"
      add :payment_method, :string, size: 20, null: false, default: "CASH"
      add :subtotal, :decimal, precision: 14, scale: 2, null: false, default: 0
      add :tax, :decimal, precision: 14, scale: 2, null: false, default: 0
      add :total, :decimal, precision: 14, scale: 2, null: false, default: 0
      add :notes, :string, size: 400
      add :sold_by, :binary_id
      add :voided_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sales, [:tenant_id, :number])
    create index(:sales, [:tenant_id, :inserted_at])
    create constraint(:sales, :sales_total_not_negative, check: "total >= 0")

    create table(:sale_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :sale_id, references(:sales, type: :binary_id, on_delete: :delete_all), null: false
      add :product_id, references(:products, type: :binary_id, on_delete: :restrict), null: false

      # Copia del nombre y del precio en el momento de la venta: el historico no
      # cambia si el producto se renombra o se le ajusta el precio.
      add :product_name, :string, size: 160, null: false
      add :quantity, :integer, null: false
      add :unit_price, :decimal, precision: 14, scale: 2, null: false
      add :tax_rate, :decimal, precision: 5, scale: 2, null: false, default: 19.00
      add :tax_amount, :decimal, precision: 14, scale: 2, null: false, default: 0
      add :total, :decimal, precision: 14, scale: 2, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:sale_items, [:sale_id])
    create constraint(:sale_items, :sale_items_quantity_positive, check: "quantity > 0")
  end
end
