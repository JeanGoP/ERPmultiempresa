# Estado de implementación del motor ERP

Este documento controla el avance del requerimiento arquitectónico sin confundir estructura preparada con funcionalidad terminada.

## Principio de protección

El modo local del lector y sus borradores se conservan. La escritura en SQL Server solo ocurre al elegir modo API, autenticarse, seleccionar una empresa autorizada y confirmar explícitamente la contabilización.

## Implementado y probado

- Base SQL Server compartida con `EmpresaId`, esquemas por dominio y Row-Level Security.
- Usuarios, roles, credenciales PBKDF2, sesiones revocables y autorización por empresa.
- Permisos granulares por operación aplicados en la API.
- Artículos, unidades, conversiones, bodegas, ubicaciones y lotes.
- Motor, chasis, VIN, serial, color y modelo desde el XML hasta la unidad física recibida.
- Documentos de proveedor mixtos con líneas de inventario, servicios, costos adicionales y activos.
- Recepciones completas, atómicas e idempotentes.
- Causaciones separadas del Kardex con cuentas, centro de costo, proyecto y comprobante balanceado.
- Saldos por artículo/bodega y opcionales por ubicación/lote.
- Kardex inmutable, promedio ponderado móvil, salidas al promedio y control de negativos.
- Distribución exacta y aplicación segura de fletes y otros costos adicionales.
- Traslados con origen, tránsito y destino conservando el valor total.
- Devoluciones a proveedor limitadas por la recepción original.
- Devoluciones de venta y ciclo de vida consultable de unidades serializadas.
- Conteos físicos con faltantes, sobrantes y detección de movimientos posteriores al corte.
- Deterioros separados del costo histórico del Kardex.
- Cierre, fotografía versionada y reapertura auditada de periodos.
- Outbox transaccional para movimientos, comprobantes y deterioros.
- Consumidor Outbox concurrente con entrega idempotente, webhook configurable, espera exponencial, descarte y reintento administrado.
- Salud viva/lista, correlación HTTP, métricas de proceso, estado por empresa y alertas operativas.
- Respaldo con checksum y manifiesto SHA-256, restauración aislada y DBCC CHECKDB.
- Archivo por lotes de periodos cerrados sin eliminar el Kardex original.
- API .NET conectada mediante proxy local, con endpoints de consultas y operaciones protegidos.
- Entorno visual ERP con acceso local, cierre de sesión y selector multiempresa.
- Menú de Compras para Entrada automática, Entrada manual y Causación de servicios.
- Bandera persistente Local/API con autenticación, empresas y catálogos reales en modo API.
- Maestros visuales por empresa para proveedores, artículos, servicios, unidades y bodegas.
- Conversiones por artículo, por ejemplo `1 caja = 12 unidades`.
- Homologación proveedor + código externo hacia el artículo y la unidad interna.
- Bandeja de líneas XML pendientes con control de avance hasta completar todas las asociaciones.
- API y procedimientos SQL auditados para crear o actualizar maestros y homologaciones.
- Consulta de inventario histórico y unidades por serial, motor, chasis, VIN y placa.
- Excepciones de inventario negativo, regularización, conciliación y reversa de movimientos.
- Respuestas SQL uniformes con código, trazabilidad y clasificación reintentable.
- Entrada automática por etapas: documento borrador, recepción preparada y contabilización confirmada.
- XML original, SHA-256, CUFE, descuentos por línea, impuestos, fletes, motor, chasis y VIN persistidos.
- Prevención de duplicados por CUFE, hash y proveedor + tipo + número.
- Consulta visual del estado del documento y de los movimientos de Kardex resultantes.
- Entrada manual conectada al mismo documento de proveedor, recepción y Kardex de la entrada XML.
- Descuentos, impuestos, cargos y costo capitalizable calculados y validados por línea manual.
- Lote, vencimiento, serial, motor, chasis, VIN, color y modelo persistidos desde la captura manual.
- Causación visual de servicios conectada a periodos y cuentas contables reales de la empresa.
- Retenciones por línea, cuenta de gasto, centro de costo, proyecto, impuestos y cuenta por pagar.
- Comprobante contable balanceado visible, separado de la recepción y sin movimientos de Kardex para servicios.
- Rol de auxiliar de bodega con panel de recepción física para chulear motos recibidas, con novedad o no recibidas antes de contabilizar el ingreso a bodega.

## Pruebas automatizadas actuales

- Regresión sintáctica y funcional del lector XML.
- Promedio ponderado, salidas, idempotencia y auditoría.
- Aislamiento de lectura y bloqueo de escritura entre empresas.
- Documento mixto y separación entre recepción y causación.
- Prorrateo y aplicación tardía de costos.
- Recepciones, causaciones, traslados, devoluciones y conteos.
- Cierre y reapertura de periodos.
- Motor, chasis y VIN vinculados a unidades serializadas.
- Eventos Outbox y deterioros.
- Compilación .NET sin advertencias.
- Prueba HTTP aislada sobre una base temporal con las 40 migraciones.
- Salud, login, permisos, rechazo anónimo `401`, denegación `403` y aislamiento entre empresas.
- Consultas HTTP de saldos, inventario histórico y unidades serializadas.
- Validaciones HTTP y traducción uniforme de errores de negocio.
- Prueba concurrente de 120 contabilizaciones sin pérdida de cantidades, valores ni secuencias.
- Regresión visual del lector actual sin errores de consola.
- Prueba integral de entrada XML: repetición del guardado, preparación y contabilización sin duplicar inventario, conservando motor y chasis.
- Prueba integral de entrada manual: idempotencia, lote, vencimiento y trazabilidad serializada, comparando su costo de Kardex con una entrada XML equivalente.
- Prueba visual del borrador manual con descuento, impuesto, cargo, seriales y total, sin errores de consola.
- Prueba integral de factura mixta: una recepción, una causación, comprobante balanceado, idempotencia y cero Kardex para la línea de servicio.
- Prueba visual de servicios con descuento, impuesto, retención y cuenta por pagar, sin errores de consola.
- Prueba operacional de Outbox, alerta, reintento y archivo conservando Kardex.
- Prueba de volumen de 5.000 movimientos con 20 trabajadores sin pérdida de cantidad, valor o secuencia.
- Ensayo integral de respaldo y restauración con resultado `TECHNICALLY_READY`.

## Pendiente para las siguientes entregas

- Completar la escritura de todos los formularios de maestros visuales en modo API; la homologación usada por el XML ya escribe en la API.
- Migración opcional de borradores locales manuales hacia SQL Server.
- Configurar y probar el webhook del sistema contable real en infraestructura de ensayo.
- Reversiones compuestas de documentos completos, además de la reversa individual de movimientos ya disponible.
- Repetir volumen, respaldo y restauración con datos e infraestructura representativos de la empresa.
- Obtener autorizaciones contable, tributaria, NIIF, inventarios, seguridad y continuidad antes de producción.
