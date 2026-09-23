# Comprobantes de egreso — primera entrega

Tesorería → Comprobantes de egreso permite preparar y recuperar borradores por empresa.
Permiso: `TESORERIA.EGRESO.PREPARAR`; el superadministrador puede acceder. Los demás usuarios
requieren asignación explícita. No se amplían permisos de compras o administración.

Un borrador tiene sucursal, beneficiario activo, fecha, moneda, medio de pago, concepto,
referencia y líneas de facturas o gastos. Banco/caja y cuentas son propuestas opcionales,
no catálogos validados. El código B-id identifica el borrador, NO un comprobante oficial.
Los abonos se validan contra el beneficiario, moneda, saldo y fecha de reconocimiento.
No se repiten facturas. Hasta 100 líneas, importes con dos decimales. API y RLS aíslan empresas.
La operación GUID evita doble guardado; la versión impide sobrescribir ediciones concurrentes.
Cada guardado efectivo queda auditado. Los listados tienen páginas de 50 borradores.

**No contabiliza, no reserva saldo, no descuenta cartera y no envía a Zeus.**
Los períodos, banco/caja, cuentas e impuestos de gastos deben validarse al implementar
la contabilización; hoy se permite preparar borradores sin período abierto. Tampoco hay
reversión, anticipos, PDF de comprobante oficial ni eliminación de borradores todavía.

## Contrato Zeus existente

Scripts suministrados por el propietario: `spWSG_Contabilidad` (Iden 16) llama a
`spWSG_ProcesarComprobantes` y este a `spInsertarDatosEnContabilidad`.
El validador distingue egresos con `Fuentes.IDTIPDOC='003'`; valida cartera mediante
INDCPITRA, TIPOFAC, NUMEFAC y VENCEFAC, además del proveedor/tercero.
No se requiere pedir nuevamente esos procedimientos. Falta verificar los efectos de
los triggers de DOCUMENT/TRANSAC y la identificación completa de la obligación en Zeus.

Ejecutar `database/scripts/inspect-zeus-disbursements.sql` en la base Zeus de pruebas:
solo consulta metadatos, definiciones de triggers y dependencias directas. Si las definiciones
están cifradas o no son visibles, solicitar a soporte Zeus la documentación o scripts originales.
No se infiere el éxito de cartera únicamente porque exista DOCUMENT/TRANSAC.

## Siguiente entrega

1. Verificar aplicación por factura y consulta del saldo de Zeus con el contrato real.
2. Maestro de bancos/cajas y catálogo de gastos ligado al plan contable de cada empresa.
3. Fuente EGRESO obligatoria por sucursal (sin reutilizar la fuente de compras como fallback).
4. Contabilización ERP transaccional: período abierto, revalidar saldo bajo bloqueo,
   aplicaciones por factura, movimiento financiero y envío duradero con snapshot.
5. Envío idempotente a Zeus, estados visibles, conciliación de resultados inciertos;
   no reenviar automáticamente si pudo haberse confirmado.
6. PDF y reversión coordinada, sin editar ni borrar pagos contabilizados.

Migración 058: `cxp.EgresoBorrador`, tres predicados RLS y permiso de preparación.
El reinicio de pruebas incluye esta tabla. No hay migración ni modificación en Zeus externo.
