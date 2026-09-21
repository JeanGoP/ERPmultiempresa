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

No incluye pantalla de configuración ni integración de botones en el frontend.
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
