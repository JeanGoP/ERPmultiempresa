# Fuentes automáticas de Zeus

Configuración de empresa → Fuentes automáticas permite definir sucursal/punto, movimiento, fuente, serie y usuarios. No hay selector en la entrada de mercancía.

Las sucursales se crean en Datos maestros → Sucursales (código, nombre y estado). Las reglas seleccionan una sucursal activa de la empresa mediante su ID; no admiten nombres libres ni IDs de otras empresas. Se pueden editar sucursales, pero no desactivar las que tengan reglas asignadas. La administración requiere el permiso de administración de seguridad. Una asignación antigua por nombre debe guardarse con el selector antes de renombrar esa sucursal.

- La asignación específica del usuario prevalece sobre la predeterminada del movimiento.
- Solo se permite una asignación por usuario/movimiento y una predeterminada por movimiento. Una sucursal no puede tener fuentes distintas para el mismo movimiento.
- Sin reglas para entradas se conserva la fuente general existente. Con reglas, un usuario sin asignación ni predeterminada deja el envío pendiente de corregir, sin escoger una fuente arbitraria.
- Los usuarios deben estar activos y pertenecer a la empresa, o ser superadministradores. Asignar fuente no concede permisos contables.
- Se usa el usuario autenticado que contabiliza o prepara el envío. Una vez preparado, fuente, serie y sucursal quedan congeladas en el snapshot, también al reintentar desde otra sesión. Si nunca pudo prepararse, la recuperación resuelve la asignación del operador que la realiza.
- Facturación, recibos de caja y egresos son configuraciones preparatorias; no activan módulos ni contabilizaciones aún no implementados.
- Las fuentes y series deben corresponder a las existentes en Zeus; no se crean allí ni se consulta automáticamente su catálogo.

Persistencia: migración 055_company_branches crea core.Sucursal con aislamiento RLS y códigos/nombres únicos por empresa. Incorpora nombres de sucursal de reglas existentes con códigos S1, S2, etc., sin alterar configuraciones ni snapshots anteriores. Las nuevas reglas guardan SucursalId en el JSON de core.ZeusConfiguracion; los comprobantes conservan su fuente y sucursal histórica. Crear y editar sucursales genera auditoría.
