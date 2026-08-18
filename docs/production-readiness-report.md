# Informe de preparación técnica para producción

Fecha del ensayo: 2026-08-16, zona America/Bogota.

Resultado automatizado: **TECHNICALLY_READY**. Este resultado no equivale a autorización para usar datos productivos.

## Evidencia aprobada

| Control | Resultado |
|---|---|
| Cliente, parser XML y API | Correcto; API con 0 errores y 0 advertencias |
| Migraciones | 38 aplicadas idempotentemente |
| Regresión SQL | Todos los escenarios, incluido `production-operations.sql`, correctos |
| Prueba HTTP | Puntos 1 a 9, readiness, permisos, operaciones y Outbox correctos |
| Outbox | Reclamo concurrente, entrega idempotente, reintento y alerta correctos |
| Archivo | Copia de periodo cerrado correcta; Kardex original conservado |
| Volumen | 5.000 movimientos, 20 trabajadores, 43,68 s, 114,48 ops/s |
| Integridad bajo carga | Sin pérdida de cantidad, valor ni secuencia |
| Respaldo | `BACKUP CHECKSUM` y `RESTORE VERIFYONLY` correctos |
| Restauración | Base aislada, 38 migraciones y `DBCC CHECKDB` correctos |

Último respaldo del ensayo: `database/backups/NexoErpDev-20260816-172609.bak`. Su manifiesto contiene tamaño, SHA-256 y hora UTC.

## Condiciones todavía bloqueantes

1. Configurar y probar el webhook HTTPS del sistema contable real; el entorno local permanece en modo `Ledger`.
2. Repetir carga, respaldo y restauración en un ambiente de ensayo equivalente a la infraestructura final.
3. Definir RPO, RTO, retención, guardias y destinos de alertas con infraestructura.
4. Obtener revisión contable, tributaria, NIIF, inventarios, seguridad y continuidad.
5. Completar todas las firmas de [go-live-approval.md](go-live-approval.md).

Hasta cerrar estos puntos, el sistema está preparado técnicamente para la siguiente fase de ensayo, pero no autorizado para operación productiva.
