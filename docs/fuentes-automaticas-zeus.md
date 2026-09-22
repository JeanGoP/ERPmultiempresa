# Fuentes automáticas de Zeus

Configuración de empresa → Fuentes automáticas permite definir sucursal/punto, movimiento, fuente y serie. No hay selector de fuentes en la entrada de mercancía.

Las sucursales se crean en Datos maestros → Sucursales (código, nombre y estado). Las reglas seleccionan una sucursal activa de la empresa mediante su ID; no admiten nombres libres ni IDs de otras empresas. Se pueden editar sucursales, pero no desactivar las que tengan reglas asignadas. La administración requiere el permiso de administración de seguridad. Una asignación antigua por nombre debe guardarse con el selector antes de renombrar esa sucursal.

- La fuente depende exclusivamente de sucursal y movimiento. No hay asignaciones de usuarios ni fuente predeterminada entre sucursales.
- Una sucursal puede tener varias bodegas. Cada bodega se asigna a una sucursal activa desde Datos maestros → Bodegas → Editar. No se infieren asignaciones para bodegas existentes.
- Al contabilizar, todas las bodegas deben tener sucursal. Si hay una sola sucursal entre todas las líneas, se toma automáticamente. Si hay varias, el formulario exige seleccionar cuál registra la entrada entre las participantes. El servidor vuelve a comprobar la distribución en la misma transacción del ERP.
- La sucursal se fija en inv.RecepcionMercancia.SucursalId; no cambia con traslados o reasignaciones posteriores de bodegas. Una vez preparado el comprobante, su fuente y serie también permanecen fijas en el snapshot.
- Sin reglas para entradas se conserva la fuente general existente. Con reglas debe existir la de la sucursal que registra; si falta, Zeus queda pendiente de corregir sin escoger la de otra sucursal.
- Las antiguas listas de usuarios se conservan solo para leer snapshots históricos; no se usan al resolver fuentes nuevas y se vacían al guardar configuración. No cambia los permisos de contabilización.
- Facturación, recibos de caja y egresos son configuraciones preparatorias; no activan módulos ni contabilizaciones aún no implementados.
- Las fuentes y series deben corresponder a las existentes en Zeus; no se crean allí ni se consulta automáticamente su catálogo.

Persistencia: migración 055_company_branches crea core.Sucursal con aislamiento RLS y códigos/nombres únicos por empresa. Incorpora nombres de sucursal de reglas existentes con códigos S1, S2, etc., sin alterar configuraciones ni snapshots anteriores. Las nuevas reglas guardan SucursalId en el JSON de core.ZeusConfiguracion; los comprobantes conservan su fuente y sucursal histórica. Crear y editar sucursales genera auditoría.

Migración 056_receipt_branch_routing agrega SucursalId a bodegas y entradas, con claves foráneas por empresa y protección contra cambios de la sucursal contable ya guardada. No modifica entradas anteriores ni asigna sus sucursales retroactivamente.
