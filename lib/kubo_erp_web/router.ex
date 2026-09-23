defmodule KuboErpWeb.Router do
  use KuboErpWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug KuboErpWeb.Plugs.Identity
  end

  # Rutas publicas: solo la sonda de salud (el gateway la consulta directamente).
  scope "/api/v1", KuboErpWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  # Rutas de negocio: exigen identidad verificada por el API Gateway.
  scope "/api/v1", KuboErpWeb do
    pipe_through [:api, :authenticated]

    get "/products/stats", ProductController, :stats
    resources "/products", ProductController, except: [:new, :edit]

    get "/stock/movements", StockController, :index
    post "/products/:id/stock", StockController, :adjust

    get "/sales/stats", SaleController, :stats
    post "/sales/:id/void", SaleController, :void
    resources "/sales", SaleController, only: [:index, :show, :create]
  end
end
