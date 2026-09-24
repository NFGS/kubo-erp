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

Las pruebas son puras (aritmética de dinero y outbox) y no necesitan base de
datos. La imagen de ejecución no incluye `test/` y el contenedor de producción se
queda sin memoria al compilar el entorno de pruebas, así que se ejecutan con 3 GB
y el directorio montado:

```bash
docker run --rm -m 3g -e MIX_ENV=test \
  -v "$PWD/test:/app/test:ro" --entrypoint bash kubo-kubo-erp \
  -c "cd /app && mix compile >/dev/null 2>&1 && ERL_LIBS=/app/_build/test/lib \
      elixir -e 'ExUnit.start(); Code.require_file(\"test/kubo_erp/sales_totals_test.exs\"); \
      Code.require_file(\"test/kubo_erp/outbox_test.exs\")'"
```

## Decisiones de diseño

- **`products.stock` es una proyección**: la verdad está en `stock_movements`,
  que permite reconstruir cualquier saldo y auditar diferencias.
- **Sin llave foránea hacia el CRM**: `customer_id` es una referencia lógica y el
  nombre del cliente se copia en la venta. Los servicios no comparten base de
  datos; el histórico no depende de la disponibilidad de otro servicio.
- **El número de venta** se calcula dentro de la transacción y el índice único
  `(tenant_id, number)` protege la secuencia; ante una colisión se reintenta.
- **Aislamiento impuesto por el motor**: RLS activo con `FORCE`; el interceptor
  `action/2` fija `app.tenant_id` por petición y las operaciones de negocio usan
  savepoints (`Repo.scoped_transaction/1`) para que un rollback de negocio no
  aborte la transacción externa (ADR-0010). `outbox_events` queda fuera de RLS a
  propósito: es la tabla operativa que el publicador lee cruzando negocios.

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
