# Roadmap incremental de Nexo ERP

## Regla de trabajo

El proyecto avanzara por entregas pequenas y demostrables. Al finalizar cada entrega se ejecutaran las pruebas del lector XML, la API y la base de datos; despues se mostrara el resultado antes de comenzar la siguiente.

La entrada de mercancia automatica actual queda protegida: no se reemplazara ni se conectara directamente al nuevo motor hasta que exista una bandera de activacion y una prueba de regresion satisfactoria.

## Punto de partida verificado

### Funciona actualmente

- Lector XML DIAN en el navegador.
- Extraccion de proveedor, factura, fechas, articulos, servicios, fletes, descuentos e impuestos.
- Extraccion y visualizacion de motor, chasis, VIN y seriales.
- Exportacion del resultado a Excel.
- Borradores locales de entradas manuales.
- Compilacion del cliente, prueba funcional del parser y compilacion de la API sin errores.
- Motor SQL Server multiempresa hasta la migracion 036.
- Kardex, saldos, costos, recepciones, causaciones, traslados, devoluciones, conteos, periodos, deterioros, seriales, reversas y auditoria.
- Prueba concurrente de 120 contabilizaciones simultaneas sin perdida de cantidad, valor o secuencia.

### Corte parcial que ya fue cerrado

- La API publica historicos, seriales, negativos, deterioros, conciliacion y reversas.
- Los permisos granulares estan aplicados a cada operacion sensible.
- La prueba HTTP aislada valida autenticacion, permisos, empresa, consultas y errores.

### Capacidades conectadas en las entregas 2 a 8

- La pantalla web inicia sesion contra la API y permite seleccionar empresa.
- El XML original se guarda con hash y control de duplicados.
- La homologacion visual resuelve codigos del proveedor contra articulos internos.
- Las entradas automaticas, manuales y causaciones de servicio usan los motores transaccionales.
- La operacion diaria, los costos y los controles avanzados tienen pantallas dedicadas.

## Entrega 1 - Cerrar y estabilizar la API (completada)

Objetivo: terminar solamente el corte que quedo parcialmente desarrollado, sin cambiar la pantalla actual.

- Publicar los endpoints nuevos ya implementados en los repositorios.
- Aplicar permisos por accion a los endpoints sensibles.
- Corregir respuestas y manejo uniforme de errores SQL.
- Probar login, empresa, permisos, consulta de saldos, historicos, seriales y una operacion controlada.
- Actualizar la documentacion de 18 a 32 migraciones.

Criterio de aceptacion: API compilada, prueba HTTP automatizada satisfactoria y lector XML sin cambios visuales ni funcionales.

Resultado: completada. La API compila sin advertencias, la prueba HTTP sobre una base temporal aprueba y la pantalla existente conserva su estructura sin errores de consola. Endpoints y permisos: [api.md](api.md).

## Entrega 2 - Crear el entorno visual del ERP (completada)

Objetivo: convertir el lector en el modulo **Entrada de mercancia automatica** dentro de un entorno ERP.

- Pantalla de inicio de sesion.
- Selector de empresa.
- Menu lateral por modulos.
- Modulo Compras con las opciones:
  - Entrada automatica por XML.
  - Entrada manual de mercancia.
  - Causacion de servicios.
- Mantener intacta la pantalla actual dentro de la opcion Entrada automatica.
- Incorporar una bandera de activacion para trabajar con datos locales o con la API.

Criterio de aceptacion: se puede entrar al ERP, seleccionar empresa y abrir el lector XML actual sin perder ninguna funcion.

Resultado: completada. Existe acceso local, selector y cambio de empresa, cierre de sesion, menu de Compras con sus tres flujos y bandera Local/API. El lector XML se conserva dentro de Entrada automatica y supero la regresion funcional y visual.

## Entrega 3 - Maestros y homologacion de articulos (completada)

Objetivo: preparar los datos necesarios antes de contabilizar una factura real.

- Proveedores.
- Articulos y servicios.
- Unidades de medida y conversiones.
- Bodegas y ubicaciones.
- Configuracion de seriales, lotes y vencimientos.
- Homologacion del codigo del proveedor con el articulo interno.
- Bandeja de lineas XML no reconocidas.

Criterio de aceptacion: cada linea del XML queda asociada a un articulo, servicio o costo adicional antes de continuar.

Resultado: completada. Los maestros se administran por empresa, las unidades admiten conversiones, los articulos configuran inventario, lote, vencimiento y seriales, y la factura muestra una bandeja que pasa de pendiente a homologada linea por linea. SQL y API conservan permisos, auditoria e idempotencia.

## Entrega 4 - Entrada automatica de mercancia

Objetivo: conectar de forma controlada el flujo que ya funciona con SQL Server.

- Guardar el XML original y su hash.
- Evitar facturas duplicadas por CUFE, numero y proveedor.
- Crear el documento de proveedor como borrador.
- Revisar descuentos, impuestos, fletes, motor, chasis y VIN.
- Preparar la recepcion.
- Contabilizar el Kardex solo mediante confirmacion del usuario.
- Mostrar el resultado y los movimientos generados.

Criterio de aceptacion: una factura DIAN de prueba se analiza, valida, guarda y contabiliza de manera idempotente; repetirla no duplica inventario.

Resultado: completada. El modo API autentica usuarios y empresas reales, carga maestros, bodegas y periodos, guarda el XML original con hash y CUFE, evita duplicados tambien por proveedor + tipo + numero, prepara sin afectar Kardex y exige una confirmacion explicita para contabilizar. La pantalla muestra estado, seriales y movimientos generados. La prueba HTTP repite documento, preparacion y contabilizacion sin duplicar inventario.

## Entrega 5 - Entrada manual de mercancia

Objetivo: registrar compras que no ingresen inicialmente mediante XML.

- Cabecera de proveedor y factura.
- Lineas de articulos.
- Descuentos, impuestos y cargos por linea.
- Captura de lote, vencimiento, serial, motor, chasis y VIN.
- Borrador, validacion y contabilizacion.
- Reutilizar exactamente el mismo motor de recepcion y Kardex de la entrada automatica.

Criterio de aceptacion: una entrada manual produce el mismo resultado contable y de inventario que una entrada equivalente originada en XML.

Resultado: completada. La captura manual en modo API crea el mismo documento de proveedor, prepara la misma recepcion y contabiliza mediante el mismo Kardex que la entrada XML. La pantalla valida bodega, periodo, articulo interno, descuentos, impuestos y cargos; tambien captura lote, vencimiento y una unidad serializada por cantidad con serial, motor, chasis, VIN, color y modelo. La prueba HTTP confirma idempotencia y el mismo costo capitalizable para una entrada XML y una manual equivalentes. Los borradores locales anteriores permanecen disponibles.

## Entrega 6 - Causacion de servicios

Objetivo: separar claramente los servicios de la mercancia.

- Facturas exclusivamente de servicios y facturas mixtas.
- Cuenta contable por linea.
- Centro de costo y proyecto.
- Impuestos y retenciones.
- Comprobante balanceado y cuenta por pagar.
- Confirmacion de que el servicio no genera movimientos de inventario.

Criterio de aceptacion: una factura mixta genera una recepcion de mercancia y una causacion independiente, sin duplicar valores.

Resultado: completada. Las facturas puras de servicios y las facturas mixtas crean una causacion independiente de la recepcion. La pantalla permite asignar cuenta por linea, centro de costo, proyecto, periodo contable, cuenta de impuesto, retencion y cuenta por pagar. La contabilizacion exige confirmacion explicita, publica el comprobante balanceado y mantiene los servicios fuera del Kardex. La prueba HTTP repite la contabilizacion sin duplicar comprobantes y confirma que una factura mixta cierra ambos flujos.

## Entrega 7 - Operacion diaria de inventarios (completada)

Objetivo: habilitar las consultas y operaciones habituales.

- Existencias por empresa, bodega, ubicacion y lote.
- Kardex e inventario a una fecha.
- Consulta por motor, chasis, VIN o serial.
- Traslados entre bodegas.
- Devoluciones a proveedor y devoluciones de venta.
- Alertas de vencimiento.

Criterio de aceptacion: cada unidad serializada conserva su estado, bodega e historial durante todo el ciclo.

Resultado: completada. La pantalla consulta existencias, Kardex e inventario historico; busca unidades por serial, motor, chasis o VIN; ejecuta traslados con despacho y recepcion; registra devoluciones de compra y venta; y publica alertas de vencimiento. La prueba HTTP confirma que una motocicleta trasladada conserva identificadores, estado, bodega e historial.

## Entrega 8 - Costos y controles avanzados (completada)

Objetivo: activar las capacidades ya preparadas en el motor SQL.

- Fletes y otros costos de adquisicion, incluso tardios.
- Libros y politicas de costo.
- Deterioros y reversiones de deterioro.
- Inventario negativo excepcional y regularizacion posterior.
- Conteos fisicos, congelamiento, reconteos y aprobaciones.
- Reversas, conciliacion y cierre de periodos.

Criterio de aceptacion: todos los ajustes conservan el costo historico y producen movimientos auditables, nunca ediciones directas del Kardex.

Resultado: completada. El modulo Costos y control administra costos de adquisicion tardios, libros y politicas versionadas, deterioros y reversiones, excepciones negativas y su regularizacion con recepciones reales, conteos con congelamiento y reconteos numerados, conciliacion, cierre, reapertura y reversas mediante contramovimientos. La API publica bandejas y trazabilidad para cada flujo. La prueba HTTP integral confirma idempotencia, costo historico inalterado y ausencia de ediciones directas del Kardex.

## Entrega 9 - Preparacion para produccion (tecnicamente completada; autorizacion pendiente)

Objetivo: llevar el sistema de una demostracion controlada a una operacion empresarial segura.

- Consumidor de eventos Outbox e integracion contable.
- Copias de seguridad y restauracion ensayada.
- Monitoreo, trazas, alertas y reintentos.
- Pruebas de volumen representativo.
- Estrategia efectiva de particionamiento y archivo segun crecimiento real.
- Revision contable, tributaria y NIIF con responsables de la empresa.
- Manual operativo y matriz de permisos.

Criterio de aceptacion: prueba integral en ambiente de ensayo y autorizacion formal antes de usar datos productivos.

Resultado tecnico: completado. La migracion 037 incorpora consumo concurrente del Outbox, entregas idempotentes, reintentos exponenciales, alertas criticas y archivo verificable sin eliminar el Kardex original. La API publica liveness, readiness, correlacion, metricas y estado operativo. Existen scripts de respaldo con checksum, restauracion aislada con DBCC CHECKDB, volumen configurable y ensayo integral. La carga local aprobo 5.000 movimientos con 20 trabajadores sin perder cantidad, valor ni secuencia; el ensayo orquestado devolvio `TECHNICALLY_READY`.

Autorizacion productiva: pendiente. Deben configurarse y ensayarse el webhook contable real y la infraestructura definitiva, y completarse las revisiones y firmas contables, tributarias, NIIF, inventarios, seguridad y continuidad descritas en [go-live-approval.md](go-live-approval.md). No se autoriza aun el uso de datos productivos.

## Proxima accion acordada

Revisar la evidencia de la **Entrega 9** y coordinar el ensayo en infraestructura definitiva. No cargar datos productivos hasta completar el acta de autorizacion formal.
