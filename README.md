# kubo-erp

Núcleo transaccional de Kubo: catálogo, inventario (kardex), ventas, compras,
caja, bodegas, facturación y documentos.

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
| GET | `/api/v1/suppliers` | Proveedores (`q`, `active`) |
| POST | `/api/v1/suppliers` | Crear proveedor |
| PATCH · DELETE | `/api/v1/suppliers/:id` | Actualizar · borrado lógico |
| GET | `/api/v1/purchases` | Compras (`status`, `supplier_id`) |
| POST | `/api/v1/purchases` | Registrar compra (suma inventario) |
| GET | `/api/v1/purchases/:id` | Detalle de compra |
| POST | `/api/v1/purchases/:id/void` | Anular compra (revierte inventario) |
| GET | `/api/v1/purchases/stats` | Totales de compras |
| GET · POST | `/api/v1/cash-sessions` · `/current` · `/:id/close` | Sesiones de caja (apertura, turno y arqueo) |
| GET · POST | `/api/v1/warehouses` · `/api/v1/transfers` | Bodegas, stock por bodega y transferencias |
| GET · POST | `/api/v1/packs` · `/packs/current` · `/packs/apply` | Vertical packs y catálogo de arranque |
| POST | `/api/v1/sales/:id/invoice` · `/invoices` · `/credit-notes` | Facturación DIAN (UBL 2.1, CUFE) y notas crédito |
| GET | `/api/v1/documents` · `/documents/:id` | Documentos del negocio (XML, PDF, soportes) |
| GET · PATCH | `/api/v1/notifications` | Buzón del negocio y marcado como leídas |
| GET | `/api/v1/reports/sales.csv` · `/reports/inventory.csv` | Reportes exportables |
| POST | `/api/v1/products/import` | Importación de catálogo por CSV |
| GET | `/api/v1/usage` · `/internal/usage` | Uso del plan (propio y agregado del operador) |
| GET | `/api/v1/health` | Estado del servicio, base y bus |

## Consistencia del inventario

1. `SELECT ... FOR UPDATE` sobre los productos implicados: dos ventas simultáneas
   no pueden vender la misma unidad.
2. La venta, su detalle y los movimientos de kardex se escriben **en una sola
   transacción**.
3. `stock_movements` tiene un índice único `(reference_type, reference_id,
   product_id, warehouse_id)`: reintentar una venta no descuenta dos veces y cada
   bodega lleva su propio kardex.
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

## Eventos y outbox transaccional

Al confirmar una venta, el evento `sale.created` (versión 1) se guarda en
`outbox_events` **en la misma transacción de la venta** (sobre estable:
`event_id`, `event_type`, `version`, `occurred_at`, `tenant_id`, `data`). Un
publicador de barrido lo entrega después a RabbitMQ (exchange `kubo.events`):
si el bus está caído, el evento espera en la bandeja y se entrega al volver. La
caja nunca depende del bus y un evento confirmado no se pierde (ADR-0009;
`make bus-drill` lo verifica). La sonda de salud expone
`outbox: {pending, published, failed}`.

## Pruebas

Son **55 pruebas ExUnit**: 34 puras (dinero, outbox, paginación, packs, planes,
facturación, PDF, documentos y adaptadores) y 21 de integración/HTTP contra
PostgreSQL real y los plugs (RLS, numeración atómica, atomicidad de la venta y el outbox,
kardex, transferencias y notas crédito). El script los corre completos con
cobertura y un **ratchet del 35 %** (hoy 36 %): la capa web y los flujos
completos los cubre el humo contra el sistema vivo:

```bash
./kubo-infra/scripts/erp-tests.sh
```

Las pruebas puras no necesitan base de datos, pero **no pueden ejecutarse dentro
del contenedor de producción**: al compilar el entorno de pruebas el contenedor
se queda sin memoria (límite de 512 MB) y la imagen de ejecución no incluye
`test/`. El script usa 3 GB y monta el árbol de trabajo (integrado en `make ci`).

## Decisiones de diseño

- **`products.stock` es una proyección**: la verdad está en `stock_movements`,
  que permite reconstruir cualquier saldo y auditar diferencias.
- **Sin llave foránea hacia el CRM**: `customer_id` es una referencia lógica y el
  nombre del cliente se copia en la venta. Los servicios no comparten base de
  datos; el histórico no depende de la disponibilidad de otro servicio.
- **El número de venta** se calcula dentro de la transacción y el índice único
  `(tenant_id, number)` protege la secuencia; ante una colisión se reintenta.
- **Aislamiento impuesto por el motor**: RLS activo con `FORCE`; el interceptor
  reserva la conexión (`Repo.checkout`) y fija `app.tenant_id` con `set_config`
  de sesión. Las operaciones de negocio abren su transacción con
  `Repo.scoped_transaction/1`, que usa savepoints cuando ya hay una transacción
  externa (por ejemplo, bajo el sandbox de pruebas) para que un rollback de
  negocio no aborte la operación completa (ADR-0010). `outbox_events` queda
  fuera de RLS a propósito: es la tabla operativa que el publicador lee
  cruzando negocios.

## Compras y proveedores (Fase 3)

La mercancía entra por una **compra** con proveedor y costo, no por un ajuste
manual. `Purchases.create/3` bloquea los productos, inserta la compra y su
detalle, **suma** el stock, deja el kardex (`reference_type = PURCHASE`),
actualiza `products.cost` con el valor **sin IVA** (el costo unitario se captura
con IVA incluido) y guarda `purchase.received` en la bandeja de salida. Anular
la compra revierte el stock con `PURCHASE_VOID` y conserva la historia. La
numeración (`C-000001`) sale del contador atómico por negocio.

## Observabilidad y calidad (Fase 2)

- **Numeración atómica**: `tenant_counters` entrega el consecutivo con un UPSERT
  (`ON CONFLICT DO UPDATE … RETURNING`); sin conflictos ni reintentos, y sin
  lecturas del máximo bajo concurrencia. `sale_items.tenant_id` está
  denormalizado para que su política de RLS sea una comparación por índice.
- **Trazas OpenTelemetry**: `opentelemetry_phoenix` (adaptador Bandit) y
  `opentelemetry_ecto` se enganchan al arrancar si hay collector; el exportador
  OTLP usa HTTP/protobuf.
- **Pruebas**: dinero, outbox y paginación son funciones puras; se ejecutan sin
  base de datos con `./kubo-infra/scripts/erp-tests.sh`.
