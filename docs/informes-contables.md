# Informes contables

Los libros y estados contables consultan en modo lectura `dbo.TRANSAC` de la base Zeus configurada para la empresa seleccionada. Incluyen movimientos vigentes (`STATUSTRA` `AC` o `XA`) anteriores a Nexo, creados directamente en Zeus y enviados por Nexo. No se suman nuevamente los asientos guardados en Nexo: Zeus es la fuente contable para estos informes. La consulta usa `MAECONT` para el nombre de la cuenta, `FUENTES` para el tipo de comprobante y `TERCEROS` para el nombre del tercero. Débitos son valores positivos de `VALORTRA`; créditos son su valor absoluto cuando `VALORTRA` es negativo.

La conexión se resuelve por `EmpresaId` desde `core.ZeusConexion`; no se acepta un servidor o una base enviada por el navegador. El permiso es `CONTABILIDAD.INFORMES.CONSULTAR`. Cada consulta limita la respuesta a 20.000 filas; una respuesta truncada no se totaliza ni se descarga como si estuviera completa. La pantalla muestra 250 filas de vista previa y el Excel incluye todas las filas consultadas y sus totales.

## Informes Zeus

- Balance de prueba, situación financiera, resultados del período, movimientos de patrimonio y efectivo/bancos.
- Libro diario, mayor por cuenta, auxiliar por tercero, comprobantes, centros de costo y cuentas utilizadas.
- Impuestos y retenciones por cuentas contables habituales.

Los saldos iniciales de balance se calculan con los movimientos Zeus anteriores a `Desde`, hasta `Hasta`; los débitos y créditos del período se cuentan desde `Desde`. Para resultados, se usan solamente los movimientos del período. Los cierres, reclasificaciones y asientos de apertura que existan en Zeus forman parte del historial consultado. La pantalla y el Excel muestran subtotales por clase, cuenta, tipo o tercero según el informe.

## Cartera Zeus e inventario Nexo

La cartera de clientes y proveedores consulta `dbo.FACTURAS_BU` de Zeus. Cada obligación se identifica por unidad de negocio, cuenta, unidad adicional, cliente/proveedor, tipo y número de factura, vencimiento y referencia. Se elige el último período de esa combinación y se muestra su `SACTFAC` vigente con signo de cliente o proveedor. Incluye obligaciones históricas que no existen en Nexo. No se aplica un filtro de fechas a este saldo vigente: `FACTURAS_BU` conserva acumulados por período y un corte arbitrario dentro del mes no puede inferirse de `SACTFAC`. El inventario valorizado sigue leyendo Nexo y se rotula como tal.

Esta lectura **no habilita aún el cobro o pago de obligaciones históricas** desde recibos y egresos: esos formularios y sus asientos todavía usan IDs de factura de Nexo. Deben incorporar la clave completa de la obligación Zeus y validar el saldo otra vez al contabilizar, sin crear facturas ficticias de venta o compra en Nexo.

Situación financiera, resultados y patrimonio requieren revisión contable de cierres y clasificación antes de presentarse como estados certificados. El informe de efectivo y bancos muestra movimientos de cuentas 11 y no sustituye un estado de flujos de efectivo. El auxiliar tributario no es un formato de información exógena DIAN.

Nexo sigue conservando sus documentos y asientos para trazabilidad y futura autonomía contable. El libro Zeus incluye el historial externo sin inventar saldos de apertura en Nexo ni duplicar documentos enviados.
