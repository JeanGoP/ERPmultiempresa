# Fuentes automáticas de Zeus

Configuración de empresa → Fuentes automáticas permite definir sucursal/punto, movimiento, fuente, serie y usuarios. No hay selector en la entrada de mercancía.

- La asignación específica del usuario prevalece sobre la predeterminada del movimiento.
- Solo se permite una asignación por usuario/movimiento y una predeterminada por movimiento. Una sucursal no puede tener fuentes distintas para el mismo movimiento.
- Sin reglas para entradas se conserva la fuente general existente. Con reglas, un usuario sin asignación ni predeterminada deja el envío pendiente de corregir, sin escoger una fuente arbitraria.
- Los usuarios deben estar activos y pertenecer a la empresa, o ser superadministradores. Asignar fuente no concede permisos contables.
- Se usa el usuario autenticado que contabiliza o prepara el envío. Una vez preparado, fuente, serie y sucursal quedan congeladas en el snapshot, también al reintentar desde otra sesión. Si nunca pudo prepararse, la recuperación resuelve la asignación del operador que la realiza.
- Facturación, recibos de caja y egresos son configuraciones preparatorias; no activan módulos ni contabilizaciones aún no implementados.
- Las fuentes y series deben corresponder a las existentes en Zeus; no se crean allí ni se consulta automáticamente su catálogo.

Persistencia: campos opcionales en el JSON existente de core.ZeusConfiguracion y en el snapshot de core.ZeusEnvio; no requiere migración. Guardar conserva auditoría y control de versión existentes. No modifica comprobantes contabilizados ni configura automáticamente empresas reales.
