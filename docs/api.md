# API Nexo ERP - corte de la Entrega 6

La API usa el prefijo `/api/v1`. Salvo salud e inicio de sesion, todas las rutas exigen un token Bearer valido y que el usuario pertenezca a la empresa indicada por `empresaId`.

## Acceso y consultas

| Metodo | Ruta | Proposito |
| --- | --- | --- |
| GET | `/health` | Comprueba conexion y numero de migraciones. |
| GET | `/health/live` | Comprueba que el proceso responde. |
| GET | `/health/ready` | Comprueba migraciones, Outbox e integración productiva. |
| POST | `/auth/login` | Autentica y entrega la sesion. |
| GET | `/companies` | Empresas autorizadas para el usuario. |
| GET | `/companies/{empresaId}/permissions` | Devuelve los permisos efectivos. |
| GET | `/companies/{empresaId}/operations/status` | Cola Outbox, entregas, alertas y métricas. |
| GET | `/companies/{empresaId}/operations/alerts` | Alertas operativas activas. |
| POST | `/companies/{empresaId}/operations/outbox/{eventId}/retry` | Reactiva un evento descartado tras corregir la causa. |
| GET | `/companies/{empresaId}/warehouses` | Bodegas de la empresa. |
| GET | `/companies/{empresaId}/inventory-periods` | Periodos abiertos o reabiertos. |
| GET | `/companies/{empresaId}/accounting-periods` | Periodos contables abiertos o reabiertos. |
| GET | `/companies/{empresaId}/accounting-accounts` | Cuentas activas que admiten movimientos. |
| GET | `/companies/{empresaId}/security/users` | Usuarios vinculados y roles asignados en la empresa. |
| GET | `/companies/{empresaId}/security/roles` | Catálogo global de roles y permisos incluidos. |
| GET | `/companies/{empresaId}/security/permissions` | Catálogo de permisos disponibles. |
| GET | `/companies/{empresaId}/supplier-documents/{id}` | Estado, XML, totales, recepción y causación. |
| GET | `/companies/{empresaId}/receipts/{id}/movements` | Movimientos de Kardex creados por la recepción. |
| GET | `/companies/{empresaId}/service-accruals/{id}` | Líneas, dimensiones, totales y comprobante de la causación. |
| GET | `/companies/{empresaId}/inventory/balances` | Existencias y valores actuales. |
| GET | `/companies/{empresaId}/inventory/history?fecha=AAAA-MM-DD&bodegaId=&articuloId=` | Inventario a una fecha. |
| GET | `/companies/{empresaId}/inventory/serialized-units?bodegaId=&estado=` | Serial, motor, chasis, VIN y placa. |

## Operaciones y permisos

| Metodo | Ruta | Permiso |
| --- | --- | --- |
| POST | `/companies/{empresaId}/inventory/entries` | `COMPRAS.RECEPCION.CONTABILIZAR` |
| POST | `/companies/{empresaId}/supplier-documents` | `COMPRAS.DOCUMENTO.CREAR` |
| POST | `/companies/{empresaId}/supplier-documents/{id}/prepare` | `COMPRAS.DOCUMENTO.CREAR` |
| POST | `/companies/{empresaId}/receipts/{id}/post` | `COMPRAS.RECEPCION.CONTABILIZAR` |
| PUT | `/companies/{empresaId}/service-accruals/{id}/accounts` | `COMPRAS.SERVICIO.CAUSAR` |
| POST | `/companies/{empresaId}/service-accruals/{id}/post` | `COMPRAS.SERVICIO.CAUSAR` |
| POST | `/companies/{empresaId}/supplier-returns/{id}/post` | `COMPRAS.DEVOLUCION.CONTABILIZAR` |
| POST | `/companies/{empresaId}/sales-returns/{id}/post` | `VENTAS.DEVOLUCION.CONTABILIZAR` |
| POST | `/companies/{empresaId}/transfers/{id}/dispatch` | `INVENTARIO.TRASLADO.DESPACHAR` |
| POST | `/companies/{empresaId}/transfers/{id}/receive` | `INVENTARIO.TRASLADO.RECIBIR` |
| POST | `/companies/{empresaId}/physical-counts/{id}/apply` | `INVENTARIO.CONTEO.APLICAR` |
| POST | `/companies/{empresaId}/landed-cost-distributions/{id}/apply` | `COSTOS.DISTRIBUCION.APLICAR` |
| POST | `/companies/{empresaId}/inventory-periods/{id}/close` | `INVENTARIO.PERIODO.CERRAR` |
| POST | `/companies/{empresaId}/inventory-periods/{id}/reopen` | `INVENTARIO.PERIODO.REABRIR` |
| POST | `/companies/{empresaId}/inventory/reconcile` | `INVENTARIO.PERIODO.CERRAR` |
| POST | `/companies/{empresaId}/inventory/impairments` | `COSTOS.DETERIORO.REGISTRAR` |
| POST | `/companies/{empresaId}/inventory/negative-exceptions` | `INVENTARIO.NEGATIVO.AUTORIZAR` |
| POST | `/companies/{empresaId}/inventory/negative-exceptions/{id}/regularize` | `INVENTARIO.NEGATIVO.AUTORIZAR` |
| POST | `/companies/{empresaId}/inventory/movements/{id}/reverse` | `INVENTARIO.AJUSTE.REVERSAR` |

## Maestros y homologacion

| Metodo | Ruta | Permiso de escritura |
| --- | --- | --- |
| GET/POST | `/companies/{empresaId}/master-data/suppliers` | `MAESTROS.PROVEEDOR.ADMINISTRAR` |
| GET/POST | `/companies/{empresaId}/master-data/units` | `MAESTROS.INVENTARIO.ADMINISTRAR` |
| GET/POST | `/companies/{empresaId}/master-data/articles` | `MAESTROS.ARTICULO.ADMINISTRAR` |
| POST | `/companies/{empresaId}/master-data/articles/{articuloId}/units` | `MAESTROS.ARTICULO.ADMINISTRAR` |
| POST | `/companies/{empresaId}/master-data/warehouses` | `MAESTROS.INVENTARIO.ADMINISTRAR` |
| GET/POST | `/companies/{empresaId}/master-data/item-mappings` | `COMPRAS.HOMOLOGACION.ADMINISTRAR` |

Las consultas requieren sesion y acceso a la empresa. Los permisos indicados se aplican a las escrituras.

## Usuarios, roles y permisos

| Metodo | Ruta | Autorización |
| --- | --- | --- |
| POST | `/companies/{empresaId}/security/users` | `SEGURIDAD.PERMISOS.ADMINISTRAR` |
| PUT | `/companies/{empresaId}/security/users/{usuarioId}` | `SEGURIDAD.PERMISOS.ADMINISTRAR` |
| PUT | `/companies/{empresaId}/security/users/{usuarioId}/password` | `SEGURIDAD.PERMISOS.ADMINISTRAR` |
| POST | `/companies/{empresaId}/security/roles` | Superadministrador global |
| PUT | `/companies/{empresaId}/security/roles/{rolId}` | Superadministrador global |

Crear un usuario genera credenciales PBKDF2 y lo vincula a la empresa mediante uno o varios roles. Si el correo ya existe en otra empresa, se conserva su contraseña y solo se agrega la nueva vinculación. Restablecer la contraseña revoca todas sus sesiones. Los administradores de seguridad asignan roles dentro de su empresa; únicamente el superadministrador puede modificar el catálogo global de roles y sus permisos.

## Entrada automatica y manual

Los dos origenes reutilizan las mismas rutas de documento de proveedor, preparacion y contabilizacion. En captura manual, cada linea puede incluir descuento, impuesto, cargo, lote, fecha de vencimiento y unidades serializadas con serial, motor, chasis, VIN, color y modelo. La consulta de movimientos de la recepcion devuelve tambien lote y vencimiento.

## Causacion de servicios

Al preparar un documento mixto, las lineas inventariables crean una recepcion y las lineas de servicio crean una causacion independiente. Las cuentas y dimensiones se validan con `PUT /service-accruals/{id}/accounts`; la confirmacion posterior genera un comprobante balanceado y una cuenta por pagar. Las retenciones reducen el valor por pagar y se acreditan en su cuenta sin generar movimientos de Kardex.

## Errores y verificacion

- `400`: datos invalidos; `401`: sesion ausente o vencida; `403`: empresa o permiso no autorizado.
- `409`: regla de negocio, duplicado, bloqueo o conflicto SQL; `500`: error inesperado sin detalles internos.
- Los errores SQL uniformes incluyen `error`, `code`, `retryable` y `correlationId`.

```powershell
npm run test:all
npm run api:smoke
```

`api:smoke` crea y elimina una base LocalDB temporal; no modifica la base de desarrollo.
