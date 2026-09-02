# Publicación manual

El backend se publica con `npm run publish:manual` después de crear el commit del trabajo.

La carpeta `publish/` contiene exclusivamente la salida de `dotnet publish` para la API ASP.NET Core en configuración Release. Los archivos del backend quedan directamente en la raíz de esa carpeta.

## Orden de despliegue

1. Respaldar la base de datos y aplicar por separado las migraciones nuevas del repositorio.
2. Configurar en el servidor la variable segura `ConnectionStrings__NexoErp`, apuntando a una instancia compartida de SQL Server. Producción rechaza explícitamente LocalDB.
3. Copiar el contenido de `publish/` al servidor de la API. El paquete no contiene `appsettings.json` y no debe reemplazar la configuración segura del servidor.
4. Verificar `/api/v1/health`, autenticación y el flujo modificado antes de habilitar usuarios.

No publiques archivos `.env`, contraseñas, respaldos ni bases locales.

`/api/v1/health` informa `databaseMode`, `databaseFingerprint` y `release`. Después de publicar, confirma que `databaseMode` sea `sqlserver` y que la versión esperada esté activa.

Las tablas operativas tienen Row-Level Security. Para una inspección administrativa directa en SSMS, establece el contexto solo durante la consulta y retíralo al finalizar:

```sql
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
SELECT * FROM ter.Tercero;
SELECT * FROM inv.Articulo;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
```
