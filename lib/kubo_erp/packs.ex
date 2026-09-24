defmodule KuboErp.Packs do
  @moduledoc """
  Paquetes de configuracion por vertical (P-17, ADR-0013).

  Un paquete adapta la terminologia, el impuesto por defecto y el flujo del
  punto de venta **sin tocar el nucleo**: el vertical es un dato del negocio
  (IAM) que viaja en el token y el gateway propaga como cabecera.

  El catalogo vive aqui porque el ERP es el dueno del nucleo comercial; IAM solo
  guarda cual tiene activo el negocio.
  """

  require Logger

  @default "retail"

  @packs %{
    "retail" => %{
      key: "retail",
      name: "Retail",
      description: "Tienda de barrio: productos con codigo de barras e inventario.",
      product_label: "Producto",
      product_label_plural: "Productos",
      default_tax_rate: "19.00",
      tracks_stock: true,
      pos_flow: "sale",
      starter_products: [
        %{sku: "ARR-001", name: "Gaseosa 400 ml", price: "3500.00", cost: "2200.00"},
        %{sku: "ARR-002", name: "Pan tajado", price: "5200.00", cost: "3800.00"},
        %{sku: "ARR-003", name: "Leche 1 L", price: "4800.00", cost: "3400.00"}
      ]
    },
    "servicios" => %{
      key: "servicios",
      name: "Servicios",
      description: "Prestacion de servicios: sin inventario ni codigos de barras.",
      product_label: "Servicio",
      product_label_plural: "Servicios",
      default_tax_rate: "19.00",
      tracks_stock: false,
      pos_flow: "sale",
      starter_products: [
        %{sku: "SRV-001", name: "Corte de cabello", price: "30000.00", cost: "0.00"},
        %{sku: "SRV-002", name: "Manicure", price: "25000.00", cost: "0.00"},
        %{sku: "SRV-003", name: "Consulta", price: "50000.00", cost: "0.00"}
      ]
    },
    "restaurantes" => %{
      key: "restaurantes",
      name: "Restaurantes",
      description: "Comida y bebida: platillos, mesas y cuentas abiertas.",
      product_label: "Platillo",
      product_label_plural: "Platillos",
      default_tax_rate: "8.00",
      tracks_stock: true,
      pos_flow: "table",
      starter_products: [
        %{sku: "PLT-001", name: "Almuerzo del día", price: "18000.00", cost: "11000.00"},
        %{sku: "PLT-002", name: "Gaseosa 400 ml", price: "4500.00", cost: "2800.00"},
        %{sku: "PLT-003", name: "Café tinto", price: "3000.00", cost: "1200.00"}
      ]
    },
    "agro" => %{
      key: "agro",
      name: "Agro",
      description: "Insumos y cosecha: lotes, bodegas y precios por bulto.",
      product_label: "Insumo",
      product_label_plural: "Insumos",
      default_tax_rate: "0.00",
      tracks_stock: true,
      pos_flow: "sale",
      starter_products: [
        %{sku: "INS-001", name: "Bulto de abono", price: "95000.00", cost: "78000.00"},
        %{sku: "INS-002", name: "Semilla de maíz 1 kg", price: "32000.00", cost: "24000.00"},
        %{sku: "INS-003", name: "Fertilizante foliar 1 L", price: "45000.00", cost: "33000.00"}
      ]
    }
  }

  @doc "Todos los paquetes, ordenados por nombre para un selector estable."
  def all, do: @packs |> Map.values() |> Enum.sort_by(& &1.name)

  @doc "Paquete por defecto del producto."
  def default, do: @packs[@default]

  @doc """
  Paquete del negocio.

  Un vertical desconocido (token viejo, dato migrado) cae al paquete por
  defecto con un aviso: el paquete solo afecta etiquetas y valores por defecto,
  no la integridad de los datos, asi que no se tumba la peticion.
  """
  def get(vertical) when vertical in [nil, ""], do: default()

  def get(vertical) do
    case Map.get(@packs, vertical) do
      nil ->
        Logger.warning("Vertical #{vertical} desconocido; se aplica #{@default}")
        default()

      pack ->
        pack
    end
  end
end
