# Integración Zeus dentro del backend

El módulo utiliza la autenticación existente y rutas por EmpresaId. No se han
modificado procedimientos de Zeus ni se han realizado contabilizaciones reales.
La migración 049 se aplica **en la base ERP**, no en CONTABILIDADMOTOCENTRO.

## Activación segura

1. Desplegar el backend y aplicar 049 en el ERP.
2. Configurar por empresa la fuente, serie, BU, usuario Zeus, tipo de factura,
   cuentas y homologaciones de proveedor/tercero. Los códigos deben ser reales,
   habilitados y compatibles con el libro y atributos de las cuentas en Zeus.
3. En el `.env` privado del servidor agregar
   `Zeus__Companies__<EmpresaId>__ConnectionString`. No se acepta ni devuelve
   la contraseña por la API. El destino de esa conexión debe coincidir exactamente
   con ServidorEsperado y BaseEsperada. No se copia `.env` a publish.
4. Consultar `connection/check`, revisar el comprobante y hacer una prueba acordada
   contra una copia de Zeus. Esta comprobación de conexión **no prueba** que la
   contabilización funcione con la versión/configuración instalada.
5. Activar `habilitado` en la configuración de esa empresa y `Zeus__Enabled=true`
   en el servidor, reiniciando la API. Sin la bandera global el despachador no
   consulta la cola. Nunca se activa por defecto durante una publicación.

## Endpoints

Base: `/api/v1/companies/{empresaId}/zeus`. Todos requieren Bearer y acceso a empresa.

| Método / ruta | Operación | Permiso |
|---|---|---|
| GET /configuration | Configuración y versión | SEGURIDAD.PERMISOS.ADMINISTRAR |
| PUT /configuration | Guardar con control optimista de versión | SEGURIDAD.PERMISOS.ADMINISTRAR |
| GET /concepts | Conceptos configurables | SEGURIDAD.PERMISOS.ADMINISTRAR |
| POST /connection/check | Lectura de conexión/objetos; no contabiliza | SEGURIDAD.PERMISOS.ADMINISTRAR |
| POST /receipts/{id}/preview | Calcular comprobante y huella | COMPRAS.RECEPCION.CONTABILIZAR |
| POST /receipts/{id}/approve | Aprobar huella y encolar | COMPRAS.RECEPCION.CONTABILIZAR |
| GET /jobs?estado=PENDIENTE&offset=0 | Estado y errores; páginas de 100 | COMPRAS.RECEPCION.CONTABILIZAR |
| POST /jobs/{id}/reconcile | Buscar y verificar un resultado incierto, sin enviar | SEGURIDAD.PERMISOS.ADMINISTRAR |

Ejemplo de configuración **ilustrativo, no son códigos listos para producción**:

```json
{
  "version": 0,
  "configuracion": {
    "habilitado": false,
    "servidorEsperado": "servidor-zeus,1433",
    "baseEsperada": "CONTABILIDADMOTOCENTRO",
    "fuente": "01", "serie": "01", "unidadNegocio": "01",
    "usuarioZeus": "ERP", "tipoFactura": "FA",
    "cuentas": [
      {"concepto":"INVENTARIO", "cuenta":"1435"},
      {"concepto":"PROVEEDOR", "cuenta":"2205"},
      {"concepto":"IVA", "tarifa":19, "cuenta":"2408"},
      {"concepto":"RETEFUENTE", "tarifa":2.5, "cuenta":"2365"}
    ],
    "proveedores": [{"proveedorId":10,"codigoProveedor":"P10","codigoTercero":"N10"}]
  }
}
```

`version=0` crea; para editar enviar la versión consultada. Las reglas admiten
`articuloId` y `proveedorId`: gana artículo específico y luego proveedor específico
frente al valor predeterminado. Las tarifas deben coincidir exactamente; no hay
tarifa fiscal predeterminada. Cada regla admite centroCosto, auxiliar, item,
presupuesto y reserva. No hay configuración por categoría en esta versión.

Ejemplo de vista previa, con importes que deben coincidir con la factura guardada:

```json
{
  "impuestos": [{"concepto":"IVA","tarifa":19,"base":100,"valor":19}],
  "retenciones": [{"concepto":"RETEFUENTE","tarifa":2.5,"base":100,"valor":2.5}]
}
```

La aprobación lleva esos mismos campos más `huella`, devuelta por preview. Si
cambió la factura o configuración, hay que revisar una vista previa nueva.
El desglose es explícito: la persistencia actual guarda importes agregados y no
permite identificar de manera fiable cada tipo/tarifa de impuesto del XML.
No se etiqueta todo impuesto como IVA ni se infiere automáticamente una retención.

## Garantías y estados

- Al contabilizar una recepción de una empresa configurada se crea
  REQUIERE_REVISION dentro de la misma transacción SQL del ERP, incluso si la
  integración está apagada. Una entrada anterior puede aprobarse por su id;
  no se envía el histórico automáticamente.
- Preview usa datos persistidos, no importes de inventario enviados por el cliente.
  Solo acepta entrada y factura contabilizadas, completas de inventario y en COP.
- Aprobar crea un snapshot de las cuentas, importes, proveedor y destino. Una
  restricción única por empresa/recepción impide encolar dos comprobantes.
- El worker toma PENDIENTE de forma atómica y lo pasa a ENVIANDO. Separa la
  transacción del ERP de la conexión/transacción de Zeus; no utiliza DTC.
- Se envía XML al `dbo.spWSG_Contabilidad`, Iden=16, dentro de una transacción
  externa. Se consumen todos los resultados, se comprueba el retorno y se
  verifican encabezado, fecha, BU, cuentas e importes antes del commit.
- `DESCDCTO` contiene `NEXO:<clave>` para identificar y conciliar el comprobante.
  Debe preservarse este marcador. El consecutivo utiliza `<serie>NUEVO`.
- Un rechazo con rollback confirmado queda RECHAZADO y puede volver a aprobarse.
  Una confirmación interrumpida, rollback no confirmado o proceso abandonado
  queda INCIERTO. No se reintenta automáticamente. La ausencia de documento en
  una consulta no se interpreta como autorización para reenviar.
- Un ENVIANDO abandonado pasa a INCIERTO después de 15 minutos cuando el worker
  está activo. Si el proceso cayó tras el commit, reconcile puede confirmar el éxito.
- La configuración no se cambia mientras hay envíos pendientes, activos o inciertos.
  Una recepción enviada/pending no puede cambiar de estado para simular una reversa
  solo en ERP. Las reversas coordinadas requieren un desarrollo posterior.

## Límites de esta entrega

La pantalla **Configuración → Integraciones → Integración Zeus** incluye configuración por empresa,
seguimiento filtrable y preparación de entradas contabilizadas. La vista previa
requiere revisar el desglose de impuestos y retenciones guardados; aprobar crea
una tarea, no una confirmación de Zeus. Los envíos inciertos solo permiten conciliar.
La pantalla muestra si el despachador del servidor está apagado; no lo activa.
Incluye cuentas configurables para CxC, anticipos, fletes, gastos, descuentos y
redondeos, pero **no genera todavía esos tipos de comprobante**. La primera ruta
genera inventario, IVA/otros impuestos explícitos, retenciones y proveedor.
Se bloquean facturas mixtas, cargos por distribuir, importes con más de dos
decimales y diferencias de cuadre; no se corrigen silenciosamente.
No crea maestros en Zeus ni aplica escenarios fiscales de ventas. Las cuentas que
exijan propiedades o unidades adicionales no soportadas pueden ser rechazadas
por Zeus. El usuario contable debe verificar cuentas, IVA descontable vs. costo,
presupuestos, permisos por día, períodos y fecha de corte antes de activar envíos.

El componente está basado en el código entregado, no en un contrato de Zeus
certificado. Se requiere una prueba contra una copia representativa de Zeus antes
de habilitar producción. Los procedimientos originales ignoran algunos códigos
de retorno; la verificación y transacción externa reducen ese riesgo sin alterarlos.

## Validaciones

`dotnet run --project tests/Zeus.Tests/Zeus.Tests.csproj -- --sql` ejecuta pruebas
de reglas/XML y del transporte contra un contrato simulado en una base desechable
en `(localdb)\MSSQLLocalDB`. Esa base se elimina al terminar. Nunca usa el `.env`
ni contabiliza en Zeus remoto. No sustituye la prueba de aceptación con Zeus real.

## Usuarios y empresa asignada

El superadministrador elige la empresa al ingresar y puede cambiar entre empresas.
En **Usuarios y permisos → Nuevo usuario** elige la empresa del nuevo usuario.
Un administrador de empresa solo puede crear usuarios dentro de su propia empresa.
Los demás usuarios ingresan directamente a su única empresa activa; la API valida
esta condición también en sesiones restauradas y peticiones posteriores.

La migración `050_single_company_users` impide nuevas asignaciones activas a varias
empresas para usuarios normales, sin borrar accesos históricos. Un usuario anterior
con varias empresas no podrá ingresar hasta que el superadministrador desactive los
accesos sobrantes. No se selecciona una empresa arbitrariamente. Se pueden mantener
varios roles dentro de la misma empresa. Las cuentas de superadministrador no se
vinculan mediante el formulario de usuarios de empresa ni se administran por sus
administradores locales.

`database/scripts/single-company-migration.ps1 -Apply` comprueba prerrequisitos,
aplica únicamente la migración 050 pendiente usando `.env` y verifica su trigger en
la base remota. No ejecuta cambios en Zeus.
# Envío manual de proveedores

En **Datos maestros → Proveedores → Enviar a Zeus**, un administrador consulta primero
el destino y la existencia del proveedor. Esta operación usa la conexión privada del
backend remoto para la empresa activa; no requiere copiarla al navegador ni al equipo local.

- `GET /api/v1/companies/{empresaId}/zeus/suppliers/{supplierId}/preview`: consulta
  existencia y asignación fija de zona, segmento y categoría fiscal; no escribe en Zeus.
- `POST /api/v1/companies/{empresaId}/zeus/suppliers/{supplierId}/send`: recibe
  `nombre1`, `apellido1` (para persona natural)
  y la `huella` de la consulta. Requiere `SEGURIDAD.PERMISOS.ADMINISTRAR`.

Solo crea lo que falta, mediante `dbo.spMae_Terceros` y `dbo.spMae_Proveedores`
con operación `I` y control transaccional `N` dentro de una transacción propia.
Necesita permisos de ejecución de esos procedimientos y consulta de sus maestros.
El tercero y el proveedor usan la identificación ERP, sin DV, máximo 10 caracteres.
No sobrescribe ni reactiva existentes y rechaza códigos incompatibles. Si falla la
creación del proveedor, revierte el tercero creado en ese intento. Repetir consulta
antes de reintentar un resultado incierto; nunca asumir éxito por un SELECT intermedio.

La cuenta se toma de la regla PROVEEDOR de la empresa, con prioridad del proveedor
específico. La división política se toma del ERP. Por instrucción del propietario,
el backend fija zona `GN`, segmento `OTROS` y categoría fiscal `OTROS`; no los pide
al usuario ni acepta sobrescribirlos desde la solicitud. Antes de crear valida que
estos códigos existan en Zeus, sin crear ni modificar los catálogos. Los datos demasiado
largos para Zeus se rechazan, no se recortan. Actualmente el alta admite los proveedores
colombianos cuya división política está calculada; otros países requieren parametrización.
Quedan auditados la solicitud y el resultado en el ERP. No envía facturas, no activa
el despachador contable y no cambia las homologaciones contables anteriores.

Tras desplegar el backend de `publish/`, probar con un solo proveedor en la base de
pruebas configurada. Las pruebas automáticas usan exclusivamente una base desechable
LocalDB, con procedimientos simulados; no demuestran permisos o compatibilidad de la
instalación remota real.
# Cuentas por bodega (migración 052)

En **Datos maestros → Bodegas → Configuración contable**, un administrador con
`SEGURIDAD.PERMISOS.ADMINISTRAR` selecciona las siete cuentas por empresa y bodega.
El backend consulta `dbo.SpMae_Maecont @Op='A'` en el destino privado de esa empresa.
El usuario SQL requiere permiso EXECUTE. No se ejecutan las opciones de creación,
modificación ni eliminación del procedimiento suministrado.

GET/PUT `/api/v1/companies/{empresaId}/zeus/warehouses/{bodegaId}/accounts` consultan
y guardan inventario, IVA compras, IVA ventas, IVA devolución ventas, ingreso,
costo de venta y devolución en venta. Se validan códigos de detalle habilitados,
excluyendo cartera y bancos. No se crea ninguna cuenta en Zeus.
La configuración queda en `core.ZeusBodegaCuenta`, con RLS, FK compuesta, versión,
destino y auditoría. Cambios concurrentes o envíos pendientes/inciertos impiden guardar.

La primera bodega configurada activa el uso de cuentas de bodega para las nuevas
preparaciones de la empresa: deben configurarse todas las bodegas que intervengan.
Se toma `RecepcionMercanciaLinea.BodegaId` o la bodega general de la entrada,
no la ubicación actual tras un traslado. Inventario e IVA compras sustituyen
las cuentas generales de esos conceptos; proveedores y retenciones siguen en
configuración de empresa. Empresas todavía sin bodegas configuradas mantienen
sus reglas anteriores. No se modifican comprobantes históricos.

En el desglose IVA puede indicarse `bodegaId`; es obligatorio distribuirlo si
las cuentas de las bodegas son diferentes. Se comprueban tarifa, base, valor,
pertenencia de la bodega a la entrada y totales. No se distribuye por suposición.
Las otras cinco cuentas se almacenan para futuros procesos de ventas/devoluciones;
esta entrega no activa esos procesos. Cambiar destino Zeus requiere revisar y
guardar las cuentas nuevamente. El worker verifica otra vez el comprobante antes de enviar.

## Cuenta general de proveedores

En Integración Zeus → Configuración de empresa → Cuentas generales se selecciona
una única **Cuenta por pagar a proveedores** para todas las bodegas. Se guarda como
regla PROVEEDOR sin artículo, proveedor ni tarifa en la configuración existente;
no requiere migración. Las dimensiones de una regla general previa se conservan.
Las excepciones históricas por proveedor requieren confirmación explícita para
ser sustituidas al guardar; no se modifican comprobantes ni maestros de Zeus existentes.

GET `/api/v1/companies/{empresaId}/zeus/supplier-accounts` consulta `SpMae_Maecont`
con opción A, filtrando detalle D, habilitada 1, indicador de cartera INDCPICTA=3.
Requiere permiso de administración de configuración, destino guardado y conexión
privada de esa empresa. PUT de configuración revalida la cuenta en Zeus y rechaza
cuentas incompatibles o reglas particulares de proveedores. Se permite guardar
el destino inicial sin cuenta únicamente con aprobaciones desactivadas.
