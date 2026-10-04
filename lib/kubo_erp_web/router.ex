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

  # Uso agregado para el panel de plataforma (ADR-0025): sin plug de identidad,
  # porque quien llama es el gateway dentro de la malla mTLS y el camino no esta
  # publicado. Recibe los negocios y responde solo conteos.
  scope "/api/v1/internal", KuboErpWeb do
    pipe_through(:api)

    get("/usage", InternalUsageController, :index)
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
    post("/sales/:id/invoice", InvoiceController, :issue)
    get("/sales/:id/invoice", InvoiceController, :show)
    post("/invoices/:id/refresh", InvoiceController, :refresh)
    post("/sales/:id/credit-note", CreditNoteController, :issue)
    get("/sales/:id/credit-note", CreditNoteController, :show)
    resources("/sales", SaleController, only: [:index, :show, :create])

    # Compras y proveedores (P-15): cierran el ciclo del inventario.
    resources("/suppliers", SupplierController, except: [:new, :edit])

    # Multi-bodega (P-22): bodegas y transferencias atomicas.
    resources("/warehouses", WarehouseController, except: [:new, :edit])
    resources("/transfers", TransferController, only: [:index, :show, :create])

    # Buzon de notificaciones (P-19).
    get("/notifications", NotificationController, :index)

    # Documentos del negocio (P-25).
    resources("/documents", DocumentController, only: [:index, :show])

    # Uso del negocio para su plan (F6.1).
    get("/usage", UsageController, :show)
    post("/purchases/:id/documents", DocumentController, :create_for_purchase)

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
