# kubo-erp
[!\[CI](https://github.com/NFGS/kubo-erp/actions/workflows/ci.yml/badge.svg)\]([https://github.com/NFGS/kubo-erp/actions/workflows/ci.yml](https://github.com/NFGS/kubo-erp/actions/workflows/ci.yml))
> Parte del proyecto **Kubo** — [kubo-workspace](https://github.com/NFGS/kubo-workspace) (ERP + CRM autoalojable para PYMES).
Núcleo transaccional de Kubo: catálogo, inventario (kardex), ventas, compras,
caja, bodegas, facturación y documentos.
<table header-row="true">
<tr>
<td>Campo</td>
<td>Valor</td>
</tr>
<tr>
<td>Stack</td>
<td>Elixir 1.17 · Phoenix 1.8 · Ecto · Bandit · AMQP</td>
</tr>
<tr>
<td>Base de datos</td>
<td>PostgreSQL 17 (`kubo_erp`)</td>
</tr>
<tr>
<td>Puerto</td>
<td>8083 (contenedor) · 9083 (host)</td>
</tr>
<tr>
<td>Ruta base</td>
<td>`/api/v1`</td>
</tr>
</table>
## Por qué Elixir aquí
La venta es la operación crítica del negocio: debe ser rápida, concurrente y
consistente. La máquina virtual de Erlang aporta procesos ligeros, aislamiento
de fallos y latencia predecible con muy poca memoria, y Ecto permite envolver la
venta completa en una transacción con bloqueo pesimista de las filas.
## Endpoints
<table header-row="true">
<tr>
<td>Método</td>
<td>Ruta</td>
<td>Descripción</td>
</tr>
<tr>
<td>GET</td>
<td>`/api/v1/products`</td>
<td>Catálogo (`q`, `low_stock`)</td>
</tr>
<tr>
<td>POST</td>
<td>`/api/v1/products`</td>
<td>Crear producto</td>
</tr>
<tr>
<td>GET</td>
<td>`/api/v1/products/:id`</td>
<td>Detalle</td>
</tr>
<tr>
<td>PATCH</td>
<td>`/api/v1/products/:id`</td>
<td>Actualizar</td>
</tr>
<tr>
<td>DELETE</td>
<td>`/api/v1/products/:id`</td>
<td>Borrado lógico</td>
</tr>
<tr>
<td>GET</td>
<td>`/api/v1/products/stats`</td>
<td>Totales y valor del inventario</td>
</tr>
<tr>
<td>POST</td>
<td>`/api/v1/products/:id/stock`</td>
<td>Ajuste de inventario (`IN`, `OUT`, `ADJUST`)</td>
</tr>
<tr>
<td>GET</td>
<td>`/api/v1/stock/movements`</td>
<td>Kardex</td>
</tr>
<tr>
<td>GET</td>
<td>`/api/v1/sales`</td>
<td>Ventas (`status`)</td>
</tr>
<tr>
<td>POST</td>
<td>`/api/v1/sales`</td>
<td>Registrar venta</td>
</tr>
<tr>
<td>GET</td>
<td>`/api/v1/sales/:id`</td>
<td>Detalle</td>
</tr>
<tr>
<td>POST</td>
<td>`/api/v1/sales/:id/void`</td>
<td>Anular venta (devuelve stock)</td>
</tr>
<tr>
<td>GET</td>
<td>`/api/v1/sales/stats`</td>
<td>Totales del día</td>
</tr>
<tr>
<td>GET</td>
<td>`/api/v1/suppliers`</td>
<td>Proveedores (`q`, `active`)</td>
</tr>
<tr>
<td>POST</td>
<td>`/api/v1/suppliers`</td>
<td>Crear proveedor</td>
</tr>
<tr>
<td>PATCH · DELETE</td>
<td>`/api/v1/suppliers/:id`</td>
<td>Actualizar · borrado lógico</td>
</tr>
<tr>
<td>GET</td>
<td>`/api/v1/purchases`</td>
<td>Compras (`status`, `supplier_id`)</td>
</tr>
<tr>
<td>POST</td>
<td>`/api/v1/purchases`</td>
<td>Registrar compra (suma inventario)</td>
</tr>
<tr>
<td>GET</td>
<td>`/api/v1/purchases/:id`</td>
<td>Detalle de compra</td>
</tr>
<tr>
<td>POST</td>
<td>`/api/v1/purchases/:id/void`</td>
<td>Anular compra (revierte inventario)</td>
</tr>
<tr>
<td>GET</td>
<td>`/api/v1/purchases/stats`</td>
<td>Totales de compras</td>
</tr>
<tr>
<td>GET · POST</td>
<td>`/api/v1/cash-sessions` · `/current` · `/:id/close`</td>
<td>Sesiones de caja (apertura, turno y arqueo)</td>
</tr>
<tr>
<td>GET · POST</td>
<td>`/api/v1/warehouses` · `/api/v1/transfers`</td>
<td>Bodegas, stock por bodega y transferencias</td>
</tr>
<tr>
<td>GET · POST</td>
<td>`/api/v1/packs` · `/packs/current` · `/packs/apply`</td>
<td>Vertical packs y catálogo de arranque</td>
</tr>
<tr>
<td>POST</td>
<td>`/api/v1/sales/:id/invoice` · `/invoices` · `/credit-notes`</td>
<td>Facturación DIAN (UBL 2.1, CUFE) y notas crédito</td>
</tr>
<tr>
<td>GET</td>
<td>`/api/v1/documents` · `/documents/:id`</td>
<td>Documentos del negocio (XML, PDF, soportes)</td>
</tr>
<tr>
<td>GET · PATCH</td>
<td>`/api/v1/notifications`</td>
<td>Buzón del negocio y marcado como leídas</td>
</tr>
<tr>
<td>GET</td>
<td>`/api/v1/reports/sales.csv` · `/reports/inventory.csv`</td>
<td>Reportes exportables</td>
</tr>
<tr>
<td>POST</td>
<td>`/api/v1/products/import`</td>
<td>Importación de catálogo por CSV</td>
</tr>
<tr>
<td>GET</td>
<td>`/api/v1/usage` · `/internal/usage`</td>
<td>Uso del plan (propio y agregado del operador)</td>
</tr>
<tr>
<td>GET</td>
<td>`/api/v1/health`</td>
<td>Estado del servicio, base y bus</td>
</tr>
</table>
## Consistencia del inventario
1. `SELECT ... FOR UPDATE` sobre los productos implicados: dos ventas simultáneas
	no pueden vender la misma unidad.
2. La venta, su detalle y los movimientos de kardex se escriben en una sola
	transacción.
3. `stock_movements` tiene un índice único `(reference_type, reference_id,<br>   product_id, warehouse_id)`: reintentar una venta no descuenta dos veces y cada
	bodega lleva su propio kardex.
4. Restricción de base de datos `products_stock_not_negative`: el motor rechaza
	cualquier estado imposible, aunque un error de programación lo intente.
## Aritmética de dinero
El precio del catálogo es el **precio final al público (IVA incluido)**, como se
usa en el comercio colombiano. Al facturar se desagrega:
```javascript
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
Las pruebas puras no necesitan base de datos, pero no pueden ejecutarse dentro
del contenedor de producción: al compilar el entorno de pruebas el contenedor
se queda sin memoria (límite de 512 MB) y la imagen de ejecución no incluye
`test/`. El script usa 3 GB y monta el árbol de trabajo (integrado en `make ci`).
## Decisiones de diseño
- **`products.stock`**** es una proyección**: la verdad está en `stock_movements`,
	que permite reconstruir cualquier saldo y auditar diferencias.
- **Sin llave foránea hacia el CRM**: `customer_id` es una referencia lógica y el
	nombre del cliente se copia en la venta. Los servicios no comparten base de
	datos; el histórico no depende de la disponibilidad de otro servicio.
- **El número de venta** se reserva en una transacción corta antes de la venta
	(el contador bloquea su fila hasta el commit y dentro de la transacción
	serializaba todas las cajas del negocio); el índice único `(tenant_id, number)`
	protege la secuencia y un fallo posterior deja un hueco que no se reutiliza.
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
## Facturación electrónica (P-18, ADR-0014)
La factura es un **puerto**: `KuboErp.Billing` define el contrato y el adaptador
se elige por configuración (`KUBO_BILLING_ADAPTER`, por defecto el `Sandbox`).
El ambiente DIAN se fija con `KUBO_BILLING_ENVIRONMENT` (1 producción, 2
habilitación) y `GET /health` reporta el adaptador activo.
- **Datos fiscales del emisor**: NIT (con DV calculado), dirección, régimen,
	resolución y prefijo viajan en el token y los propaga el gateway; el negocio
	los edita en Configuración.
- **Estados y proveedor**: la factura guarda `status`, `provider_reference` y
	`status_detail`; los adaptadores devuelven errores tipados
	(`KuboErp.Billing.Error`) y pueden implementar `refresh_status/1` si validan
	de forma asíncrona (`POST /invoices/:id/refresh`).
- **Guía para enchufar el proveedor tecnológico**:
	[`kubo-docs/13-guia-adaptador-facturacion.md`](../kubo-docs/13-guia-adaptador-facturacion.md).
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
