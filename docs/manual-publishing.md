# Publicación manual

Este paquete se genera con `npm run publish:manual` después de crear el commit del trabajo.

## Contenido

- `frontend/`: archivos estáticos listos para subir al hosting web.
- `api/`: API ASP.NET Core publicada en configuración Release.
- `database/migrations/`: migraciones SQL que deben aplicarse en orden antes de activar la nueva API.
- `VERSION.txt`: commit y fecha usados para generar el paquete.

## Orden de despliegue

1. Respaldar la base de datos.
2. Aplicar las migraciones SQL nuevas en orden, verificando cada resultado.
3. Publicar el contenido de `api/` en el servidor de la API y configurar su cadena de conexión mediante variables seguras.
4. Publicar el contenido de `frontend/` en el hosting estático.
5. Verificar `/api/v1/health`, autenticación y el flujo modificado antes de habilitar usuarios.

No publiques archivos `.env`, contraseñas, respaldos ni bases locales.
