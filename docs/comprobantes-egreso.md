# Comprobantes de egreso — contabilización definitiva (059)

Tesorería → Comprobantes de egreso → Nuevo egreso. No existe opción de guardar borrador
ni editar un egreso contabilizado. Los endpoints antiguos `disbursement-drafts` ya no se
registran; la tabla 058 se conserva para no destruir datos anteriores, sin convertirlos
automáticamente en pagos. Los borradores de entrada de mercancía no se modifican.

Permiso nuevo y crítico: `TESORERIA.EGRESO.CONTABILIZAR`. No se concede implícitamente
a quienes solo podían preparar borradores. El superadministrador conserva acceso.

Configuración inicial: fuente EGRESO por sucursal en Integración Zeus y, en Comprobantes
de egreso → Caja / banco por sucursal, cuenta y medio del catálogo MONEDAS de Zeus para
EFECTIVO / TRANSFERENCIA / CHEQUE. Se consulta el plan real; no se permite cambiar la
cuenta de salida al registrar un pago. Esa configuración requiere administración de seguridad.

Al escoger proveedor se consultan todas sus facturas pendientes del ERP. Se seleccionan
las facturas y se modifica el importe propuesto para hacer abonos. Máximo 100 aplicaciones
o gastos por comprobante, COP y dos decimales. La cuenta por pagar, tipo, número y unidad
de negocio se recuperan del snapshot de la entrada contabilizada en Zeus, no de cuentas
digitadas ni de la configuración actual si cambió. Una obligación sin entrada confirmada
en Zeus requiere conciliar su origen antes de pagar por esta integración.

La API valida período abierto, proveedor y sucursal activos, cuentas, fuente tipo 003,
medio de pago antes del registro ERP. El importe se valida contra el saldo pendiente del ERP.
En una transacción serializable crea
el CE-id, líneas débito/crédito, pagos en `cxp.MovimientoProveedor`, reduce saldos y deja
el envío durable pendiente. La GUID evita duplicados; el egreso es inmutable. No ejecuta
transferencias bancarias: registra contablemente el desembolso realizado.

El despachador usa `Zeus:Enabled=true` y el contrato existente `spWSG_Contabilidad` Iden 16.
Envía proveedor (`CLIPRV`), tercero (`NITTRA`), número (`NUMEFAC`), tipo (`TIPOFAC`),
vencimiento (`VENCEFAC`) y valor del abono (`VALORTRA`), además de cuenta, referencia y BU.
Verifica DOCUMENT y TRANSAC por factura. Zeus es responsable de aplicar su cartera:
no se exige consultar ni observar una variación inmediata de `Facturas_Bu.Sactfac`.
NO llama por su cuenta a SpPagosACartera ni escribe directamente saldos Zeus.
Un error del procedimiento o movimientos que no coinciden sí revierten el envío.
Reintentar solo Zeus nunca vuelve a aplicar el pago ERP. Los resultados inciertos se
concilian por clave, no se reenvían automáticamente. No se marcan contabilizados por
el mero hecho de existir un comprobante.

Los gastos directos de esta entrega son valores simples, sin IVA/retenciones, con cuentas
de detalle que no exigen centro de costo/ítem. Las compras con impuestos se causan antes
y se pagan como obligaciones. No incluye reversión automática ni PDF oficial todavía.

Pruebas: `npm run test:egresos` crea una base LocalDB desechable con esquema ERP completo
y un doble SQL explícito de Zeus (`tests/egreso-zeus-fixture.sql`). Prueba pagos parciales,
totales, duplicados, aislamiento, bloqueos, confirmación sin depender del acumulado de cartera,
reenvío e inmutabilidad. No es una ejecución de los procedimientos originales cifrados.
La primera prueba contra Zeus real queda pendiente hasta ejecutar desde el backend
remoto que tiene su conexión. No se hicieron pagos reales en el despliegue de este cambio.

El script de reinicio reconoce las tablas 058 y 059. Esta implementación no instala ni
modifica procedimientos de Zeus externo. El diagnóstico de solo lectura permanece en
`database/scripts/inspect-zeus-disbursements.sql` para revisar diferencias del contrato real.
