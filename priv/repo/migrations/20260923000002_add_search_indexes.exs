defmodule KuboErp.Repo.Migrations.AddSearchIndexes do
  @moduledoc """
  Indices trigram para la busqueda de productos por nombre y SKU.

  La busqueda del POS usa `ILIKE '%termino%'`, que **no puede usar un indice
  B-tree**: PostgreSQL termina recorriendo todas las filas del negocio. Medido
  con 50.000 productos:

      sin indice trigram   ~46 ms   (49.999 filas descartadas por el filtro)
      con indice trigram   ~5.7 ms  (Bitmap Index Scan, 10 filas revaluadas)

  `pg_trgm` es una extension *trusted* desde PostgreSQL 13, por lo que el rol
  dueno de la base puede crearla sin privilegios de superusuario.
  """

  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    execute """
    CREATE INDEX IF NOT EXISTS idx_products_name_trgm
    ON products USING gin (name gin_trgm_ops)
    """

    execute """
    CREATE INDEX IF NOT EXISTS idx_products_sku_trgm
    ON products USING gin (sku gin_trgm_ops)
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS idx_products_name_trgm"
    execute "DROP INDEX IF EXISTS idx_products_sku_trgm"
  end
end
