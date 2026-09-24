defmodule KuboErpWeb.Router do
  use KuboErpWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :authenticated do
    plug(KuboErpWeb.Plugs.Identity)
  end

  # Rutas publicas: solo la sonda de salud (el gateway la consulta directamente).
  scope "/api/v1", KuboErpWeb do
    pipe_through(:api)

    get("/health", HealthController, :show)
  end

  # Rutas de negocio: exigen identidad verificada por el API Gateway.
  scope "/api/v1", KuboErpWeb do
    pipe_through([:api, :authenticated])

    get("/products/stats", ProductController, :stats)
    post("/products/import", ProductController, :import)
    resources("/products", ProductController, except: [:new, :edit])

    get("/stock/movements", StockController, :index)
    post("/products/:id/stock", StockController, :adjust)

    get("/sales/stats", SaleController, :stats)
    post("/sales/:id/void", SaleController, :void)
    resources("/sales", SaleController, only: [:index, :show, :create])

    # Compras y proveedores (P-15): cierran el ciclo del inventario.
    resources("/suppliers", SupplierController, except: [:new, :edit])

    get("/purchases/stats", PurchaseController, :stats)
    post("/purchases/:id/void", PurchaseController, :void)
    resources("/purchases", PurchaseController, only: [:index, :show, :create])

    # Paquetes de configuracion por vertical (P-17).
    get("/packs", PackController, :index)
    get("/packs/current", PackController, :current)
    post("/packs/apply", PackController, :apply)

    # Reportes exportables (P-21).
    get("/reports/sales.csv", ReportController, :sales)
    get("/reports/inventory.csv", ReportController, :inventory)

    # Caja (P-16): apertura, cierre y arqueo por turno.
    get("/cash-sessions/current", CashSessionController, :current)
    post("/cash-sessions/open", CashSessionController, :open)
    post("/cash-sessions/:id/close", CashSessionController, :close)
    get("/cash-sessions/:id", CashSessionController, :show)
    get("/cash-sessions", CashSessionController, :index)
  end
end
