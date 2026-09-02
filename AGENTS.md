# Instrucciones del proyecto

Al terminar cada trabajo de implementación:

1. Ejecutar las validaciones proporcionales al cambio y corregir sus errores.
2. Para trabajo destinado a despliegue, aplicar las migraciones con `npm run db:migrate:production` usando `ConnectionStrings__NexoErp` y `ERP_API_HEALTH_URL`. El comando debe confirmar tanto SQL Server como el endpoint remoto. `npm run db:init` actualiza solo LocalDB y nunca cuenta como migración desplegada.
3. Crear un commit con un mensaje claro en español.
4. Después del commit, ejecutar `npm run publish:manual` para dejar exclusivamente el backend compilado en la carpeta local ignorada `publish/`.
5. Hacer `push` de los commits a la rama remota correspondiente.
6. Informar el hash del commit, las migraciones y validaciones realizadas, la ubicación del backend publicado y el resultado del `push`.

No incluir secretos ni bases de datos locales en el commit o en `publish/`. Si la conexión desplegada no está disponible, detenerse e informar el bloqueo; nunca afirmar que producción fue migrada basándose en LocalDB.
