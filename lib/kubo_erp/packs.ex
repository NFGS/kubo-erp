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
      pos_flow: "sale"
    },
    "servicios" => %{
      key: "servicios",
      name: "Servicios",
      description: "Prestacion de servicios: sin inventario ni codigos de barras.",
      product_label: "Servicio",
      product_label_plural: "Servicios",
      default_tax_rate: "19.00",
      tracks_stock: false,
      pos_flow: "sale"
    },
    "restaurantes" => %{
      key: "restaurantes",
      name: "Restaurantes",
      description: "Comida y bebida: platillos, mesas y cuentas abiertas.",
      product_label: "Platillo",
      product_label_plural: "Platillos",
      default_tax_rate: "8.00",
      tracks_stock: true,
      pos_flow: "table"
    },
    "agro" => %{
      key: "agro",
      name: "Agro",
      description: "Insumos y cosecha: lotes, bodegas y precios por bulto.",
      product_label: "Insumo",
      product_label_plural: "Insumos",
      default_tax_rate: "0.00",
      tracks_stock: true,
      pos_flow: "sale"
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
