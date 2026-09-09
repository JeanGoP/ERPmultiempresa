# Relación de facturas y pagos

Disponible en Informes > Relación de facturas y pagos y en Cuentas por pagar > Preparar reporte.
Seleccionar proveedor, moneda y filtros, actualizar, escoger las facturas y descargar PDF o Excel real (.xlsx).
El Excel tiene hojas Facturas y Pagos y notas, encabezados inmovilizados, filas alternadas, importes numéricos, fechas nativas, fórmulas de totales y números de factura como texto. No requiere importar separadores.
El formato se crea con Artifact Tool mediante scripts/build-payment-report-template.mjs, usando ERP_ARTIFACT_NODE_MODULES del runtime de autoría. El navegador rellena la plantilla publicada en public/assets/payment-report-template.json y empaqueta los componentes XLSX sin dependencias de servidor. Los textos del XML nunca se interpretan como fórmulas.
Solo incluye obligaciones contabilizadas. Excluye anuladas; permite incluir pagadas para consultar sus aplicaciones.
La descarga vuelve a consultar la API y no registra pagos ni modifica saldos. La referencia escrita no es un consecutivo contable.

## Comparación con el formato de referencia

El archivo `_REPORTE APLICATIVO 013 (26 -05-2026)  .xlsx`, Hoja1, presenta datos de empresa, referencia y fecha, facturas (B10:H73), descuentos y pagos (B111:E124). Contiene IVA fijo de 19%/16%, ajustes manuales y descuentos rotulados 2%/5%. No se replican esas fórmulas como reglas del ERP.

| Dato | Fuente y disponibilidad |
| --- | --- |
| Empresa y NIT | core.Empresa |
| Proveedor y NIT | ter.Tercero |
| Número, fecha, bruto, descuentos, impuestos, cargos | comp.DocumentoProveedor; se exponen en cartera y extracto |
| Neto sin impuestos | Bruto menos descuento guardado en factura |
| Otros ajustes factura | Diferencia entre valor original y neto más impuestos y cargos; no se identifica arbitrariamente como retención |
| Valor original y saldo | cxp.DocumentoPorPagar |
| Pagos aplicados | cxp.MovimientoProveedor de tipo PAGO, abono menos cargo |
| Notas crédito, aplicaciones y reversos | Movimientos separados por su tipo real, no presentados como consignaciones |
| Banco, consignación, sede del pago | No disponibles en MovimientoProveedor; falta el flujo de tesorería |
| Descuentos por pronto pago | No hay un concepto/aplicación específico implementado; no se presume 2% ni 5% |
| Saldo a favor por anticipos sin aplicar | No disponible en esta consulta por factura; no inferir de pagos de otras facturas |

Impuestos es el total capturado, no necesariamente IVA exclusivamente. Los descuentos de factura ya están incorporados en el valor original y no se restan nuevamente al saldo. Los movimientos se incluyen completos para las facturas seleccionadas, independientemente del rango de contabilización utilizado para escogerlas. Es una consulta actual, no un corte histórico ni constancia de pago.

Si el mayor de movimientos no concilia con el saldo de una factura, se advierte en la exportación. No se corrige ni se oculta esa diferencia.
La consulta mantiene los permisos de compras y el aislamiento por empresa de los endpoints existentes. No requiere migración.
Debe publicarse el backend actualizado para obtener el desglose; una API anterior genera un error explícito en vez de exportar importes faltantes como ceros.
