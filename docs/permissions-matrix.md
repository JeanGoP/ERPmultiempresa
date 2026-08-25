# Matriz mínima de permisos

Aplicar mínimo privilegio y separar solicitud, aprobación y contabilización. Los permisos críticos no deben concederse por costumbre ni compartiendo usuarios.

| Permiso | Perfil sugerido | Crítico | Control |
|---|---|---:|---|
| `COMPRAS.DOCUMENTO.CREAR` | Auxiliar de compras | No | Crea borradores |
| `COMPRAS.RECEPCION.REVISAR` | Auxiliar de bodega | No | Marca recepción física por moto |
| `COMPRAS.RECEPCION.CONTABILIZAR` | Responsable de recibo | Sí | Confirma entrada y Kardex |
| `COMPRAS.SERVICIO.CAUSAR` | Contabilidad proveedores | Sí | Genera comprobante y cuenta por pagar |
| `COMPRAS.DEVOLUCION.CONTABILIZAR` | Jefe de compras | Sí | Devuelve contra recepción original |
| `VENTAS.DEVOLUCION.CONTABILIZAR` | Jefe de ventas | Sí | Restaura costo de la salida original |
| `INVENTARIO.TRASLADO.DESPACHAR` | Bodega origen | No | No debe recibir el mismo traslado |
| `INVENTARIO.TRASLADO.RECIBIR` | Bodega destino | No | Valida recepción física |
| `INVENTARIO.CONTEO.INICIAR` | Coordinador de inventario | No | Congela alcance |
| `INVENTARIO.CONTEO.CAPTURAR` | Contador físico | No | Sin acceso a aprobar |
| `INVENTARIO.CONTEO.APROBAR` | Jefe de inventario | Sí | Diferente del capturador |
| `INVENTARIO.CONTEO.APLICAR` | Control interno | Sí | Genera ajustes de Kardex |
| `INVENTARIO.NEGATIVO.AUTORIZAR` | Gerencia operativa | Sí | Excepción temporal justificada |
| `INVENTARIO.AJUSTE.REVERSAR` | Control interno | Sí | Solo contramovimientos |
| `COSTOS.DISTRIBUCION.APROBAR` | Contador de costos | Sí | Revisa base de distribución |
| `COSTOS.DISTRIBUCION.APLICAR` | Jefe contable | Sí | Modifica valor mediante movimientos |
| `COSTOS.DETERIORO.REGISTRAR` | Contabilidad NIIF | Sí | Requiere soporte de medición |
| `INVENTARIO.PERIODO.CERRAR` | Jefe contable | Sí | Después de conciliación |
| `INVENTARIO.PERIODO.REABRIR` | Contralor | Sí | Motivo y segregación obligatorios |
| `MAESTROS.PROVEEDOR.ADMINISTRAR` | Maestro de terceros | No | Validación fiscal independiente |
| `MAESTROS.ARTICULO.ADMINISTRAR` | Maestro de productos | No | Control de unidad y serialización |
| `MAESTROS.INVENTARIO.ADMINISTRAR` | Administrador de inventario | No | Unidades, bodegas y ubicaciones |
| `COMPRAS.HOMOLOGACION.ADMINISTRAR` | Analista de compras | No | Revisión de código externo |
| `SEGURIDAD.PERMISOS.ADMINISTRAR` | Administrador de seguridad | Sí | No debe contabilizar operaciones |

Revisión trimestral: exportar permisos efectivos por empresa, confirmar responsable y fecha de expiración, retirar usuarios inactivos y documentar excepciones en `seg.UsuarioEmpresaPermiso`.
