# Publicación manual

El backend se publica con `npm run publish:manual` después de crear el commit del trabajo.

La carpeta `publish/` contiene exclusivamente la salida de `dotnet publish` para la API ASP.NET Core en configuración Release. Los archivos del backend quedan directamente en la raíz de esa carpeta.

## Orden de despliegue

1. Respaldar la base de datos y aplicar por separado las migraciones nuevas del repositorio.
2. Copiar el contenido de `publish/` al servidor de la API.
3. Configurar la cadena de conexión mediante variables seguras.
4. Verificar `/api/v1/health`, autenticación y el flujo modificado antes de habilitar usuarios.

No publiques archivos `.env`, contraseñas, respaldos ni bases locales.
