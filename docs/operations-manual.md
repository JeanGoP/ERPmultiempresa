# Manual operativo de Nexo ERP

## Propósito y alcance

Este manual cubre despliegue, disponibilidad, integración, respaldo, recuperación, monitoreo, archivo e incidentes. No sustituye la aprobación contable, tributaria, NIIF, de seguridad ni de continuidad de la empresa.

## Configuración de producción

1. Usar SQL Server administrado, no LocalDB, con una cuenta de servicio de mínimo privilegio.
2. Entregar `ConnectionStrings__NexoErp` mediante un almacén de secretos; nunca escribir credenciales en `appsettings.json`.
3. Configurar `Outbox__DeliveryMode=Webhook` y `Outbox__WebhookUrl` con HTTPS hacia la integración contable. El receptor debe respetar `Idempotency-Key`.
4. Terminar TLS en un proxy confiable, restringir `AllowedHosts` y conservar `X-Correlation-ID` en todos los componentes.
5. Ejecutar las 40 migraciones sobre un respaldo reciente y validar `/api/v1/health/ready` antes de habilitar tráfico.

`DeliveryMode=Ledger` es útil para desarrollo y ensayos, pero `/health/ready` informa `productionIntegration=false`; no satisface por sí solo la integración productiva.

## Comprobaciones de salud

- `GET /api/v1/health/live`: confirma que el proceso responde.
- `GET /api/v1/health/ready`: comprueba base, migraciones, descartes Outbox y modo de integración.
- `GET /api/v1/companies/{id}/operations/status`: muestra cola, descartes, entregas de 24 horas, alertas y métricas del proceso.
- `GET /api/v1/companies/{id}/operations/alerts`: muestra alertas activas para administradores.

Umbrales iniciales:

| Señal | Advertencia | Crítica | Acción |
|---|---:|---:|---|
| Evento Outbox más antiguo | 5 minutos | 15 minutos | Verificar receptor y red |
| Eventos descartados | — | 1 | Corregir causa y reintentar |
| Respuestas HTTP 5xx | 1 % en 5 min | 5 % en 5 min | Revisar trazas por correlación |
| Latencia promedio API | 750 ms | 2 s | Revisar SQL, bloqueos y capacidad |
| Último respaldo válido | 18 horas | 26 horas | Ejecutar respaldo y escalar |

## Outbox e integración contable

El consumidor reclama lotes con bloqueo temporal y `READPAST`, incrementa intentos y entrega cada evento con su GUID como clave idempotente. Una respuesta exitosa crea una sola fila en `core.EntregaIntegracion`. Los fallos usan espera exponencial; al agotar intentos el evento se descarta lógicamente y crea una alerta crítica.

Después de corregir el receptor, un administrador puede usar `POST /api/v1/companies/{id}/operations/outbox/{eventId}/retry`. El procedimiento reactiva el evento y resuelve la alerta; no modifica el documento de negocio.

## Respaldo y restauración

Ejecutar diariamente y antes de cada despliegue:

```powershell
npm run db:backup
```

El script crea `.bak`, ejecuta `RESTORE VERIFYONLY`, calcula SHA-256 y guarda un manifiesto JSON. Copiar ambos archivos a almacenamiento cifrado e inmutable fuera del servidor. Definir con la empresa RPO y retención; propuesta inicial: respaldo completo diario, log cada 15 minutos y retención de 35 días.

Ensayar mensualmente una restauración aislada:

```powershell
powershell -File database/scripts/verify-restore.ps1 -BackupPath "D:\Respaldos\NexoErp.bak"
```

La prueba restaura con otro nombre, ejecuta `DBCC CHECKDB`, valida al menos 40 migraciones y elimina solamente la base temporal. Registrar duración como RTO observado.

## Archivo y crecimiento

`core.PoliticaParticionKardex` define meses en línea y habilitación por empresa. `inv.usp_ArchivarKardexCerrado` solo copia movimientos de periodos cerrados anteriores al corte, por lotes e idempotentemente, a `inv.MovimientoInventarioArchivo`. El origen queda intacto (`OrigenEliminado=0`).

Revisar trimestralmente `inv.usp_DiagnosticarCapacidadInventario`. La eliminación o `SWITCH PARTITION` del origen requiere una ventana específica, copia restaurable, edición/edición de SQL Server compatible y aprobación formal; no está automatizada para evitar romper trazabilidad.

## Incidentes

1. Declarar impacto, empresa, hora y correlación.
2. Evitar correcciones directas en Kardex, saldos, Outbox o comprobantes.
3. Detener tráfico si hay riesgo de duplicidad; las operaciones idempotentes pueden reintentarse.
4. Preservar logs, alerta, payload y respaldo.
5. Recuperar mediante procedimientos del ERP o restauración; reconciliar inventario y contabilidad.
6. Documentar causa, alcance, corrección y prueba de no recurrencia.

## Ensayo previo a salida

Ejecutar `npm run production:rehearsal`. Deben aprobar compilación, parser, API, SQL, respaldo/restauración y volumen. El resultado `TECHNICALLY_READY` significa preparación técnica, no autorización empresarial. Completar [go-live-approval.md](go-live-approval.md) antes de usar datos productivos.
