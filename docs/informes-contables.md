# Informes contables de Nexo

Los informes leen únicamente la base del ERP. `cont.vw_AsientoNexo` unifica las líneas de los documentos que Nexo conserva y que ya fueron confirmados en Zeus: entradas, egresos, facturas, recibos, reversos y notas de cartera. También incluye comprobantes contabilizados directamente en `cont.ComprobanteContable`. Cada línea conserva empresa, fecha, documento, cuenta, tercero, centro de costo, débito y crédito.

La vista no consulta Zeus al generar un informe. Los documentos aún pendientes o rechazados se excluyen. La consulta está protegida por el permiso `CONTABILIDAD.INFORMES.CONSULTAR`; el rol `ADMIN` lo recibe y el nuevo rol `CONTADOR` tiene solo permiso de lectura de estos informes. La API limita las respuestas a 20.000 filas y la pantalla muestra una vista previa de 250; la descarga Excel incluye todas las filas consultadas.

## Informes disponibles

- Balance de prueba, situación financiera parcial, resultados parciales, cambios en patrimonio parciales y efectivo/bancos.
- Libro diario, mayor por cuenta, auxiliar por tercero, comprobantes, centros de costo y cuentas utilizadas.
- Impuestos y retenciones por cuentas contables habituales, cartera actual de clientes y proveedores, e inventario valorizado a fecha.

## Alcance de los datos

Los saldos históricos hechos solo en Zeus no están en Nexo y no aparecen aquí. Tampoco hay aún un asiento de apertura/importación histórica ni clasificación de flujos de efectivo o notas. Los estados parciales son papeles de trabajo y requieren conciliación antes de presentarse. La cartera muestra el saldo **actual** de documentos reconocidos dentro de las fechas filtradas, no el saldo histórico a esas fechas. El informe tributario es un auxiliar por cuentas y tercero, no un archivo de exógena DIAN.

Para que Nexo opere de forma independiente en el futuro, se deberán importar y conciliar saldos de apertura e historia, completar el maestro de cuentas por empresa y sustituir la confirmación de Zeus como condición de contabilización por un cierre contable propio de Nexo.
