# kubo-erp

Núcleo transaccional de Kubo: catálogo, inventario (kardex) y ventas.

| Campo | Valor |
| --- | --- |
| Stack | Elixir 1.17 · Phoenix 1.8 · Ecto · Bandit · AMQP |
| Base de datos | PostgreSQL 17 (`kubo_erp`) |
| Puerto | 8083 (contenedor) · 9083 (host) |
| Ruta base | `/api/v1` |

## Por qué Elixir aquí

La venta es la operación crítica del negocio: debe ser rápida, concurrente y
consistente. La máquina virtual de Erlang aporta procesos ligeros, aislamiento
de fallos y latencia predecible con muy poca memoria, y Ecto permite envolver la
venta completa en una transacción con bloqueo pesimista de las filas.

## Endpoints

| Método | Ruta | Descripción |
| --- | --- | --- |
| GET | `/api/v1/products` | Catálogo (`q`, `low_stock`) |
| POST | `/api/v1/products` | Crear producto |
| GET | `/api/v1/products/:id` | Detalle |
| PATCH | `/api/v1/products/:id` | Actualizar |
| DELETE | `/api/v1/products/:id` | Borrado lógico |
| GET | `/api/v1/products/stats` | Totales y valor del inventario |
| POST | `/api/v1/products/:id/stock` | Ajuste de inventario (`IN`, `OUT`, `ADJUST`) |
| GET | `/api/v1/stock/movements` | Kardex |
| GET | `/api/v1/sales` | Ventas (`status`) |
| POST | `/api/v1/sales` | Registrar venta |
| GET | `/api/v1/sales/:id` | Detalle |
| POST | `/api/v1/sales/:id/void` | Anular venta (devuelve stock) |
| GET | `/api/v1/sales/stats` | Totales del día |
| GET | `/api/v1/health` | Estado del servicio, base y bus |

## Consistencia del inventario

1. `SELECT ... FOR UPDATE` sobre los productos implicados: dos ventas simultáneas
   no pueden vender la misma unidad.
2. La venta, su detalle y los movimientos de kardex se escriben **en una sola
   transacción**.
3. `stock_movements` tiene un índice único `(reference_type, reference_id,
   product_id)`: reintentar una venta no descuenta dos veces.
4. Restricción de base de datos `products_stock_not_negative`: el motor rechaza
   cualquier estado imposible, aunque un error de programación lo intente.

## Aritmética de dinero

El precio del catálogo es el **precio final al público (IVA incluido)**, como se
usa en el comercio colombiano. Al facturar se desagrega:

```
total    = cantidad × precio
impuesto = total × tarifa / (100 + tarifa)
subtotal = total − impuesto
```

Se usa `Decimal` en todo el cálculo (nunca coma flotante) y las funciones
`Sales.line_amounts/3` y `Sales.totals/1` son puras: se prueban sin base de datos.

## Eventos

Al confirmar una venta se publica `sale.created` (versión 1) en el exchange
`kubo.events` de RabbitMQ, con sobre estable (`event_id`, `event_type`,
`version`, `occurred_at`, `tenant_id`, `data`). La publicación es asíncrona y
**no bloquea la venta**: si el bus está caído, se registra la advertencia y el
negocio continúa.

## Pruebas

```bash
mix test test/kubo_erp/sales_totals_test.exs
```

## Decisiones de diseño

- **`products.stock` es una proyección**: la verdad está en `stock_movements`,
  que permite reconstruir cualquier saldo y auditar diferencias.
- **Sin llave foránea hacia el CRM**: `customer_id` es una referencia lógica y el
  nombre del cliente se copia en la venta. Los servicios no comparten base de
  datos; el histórico no depende de la disponibilidad de otro servicio.
- **El número de venta** se calcula dentro de la transacción y el índice único
  `(tenant_id, number)` protege la secuencia; ante una colisión se reintenta.
