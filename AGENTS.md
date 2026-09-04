# Instrucciones del proyecto

Al terminar cada trabajo de implementación:

1. Ejecutar las validaciones proporcionales al cambio y corregir sus errores.
2. Ejecutar las migraciones pendientes en la base remota configurada, usando la conexión privada de `.env`, al terminar cada implementación que las requiera. El propietario autoriza esta ejecución de forma permanente: no pedir confirmación de nuevo para las migraciones del trabajo solicitado. Verificar primero servidor, base y migraciones aplicadas; ejecutar únicamente las pendientes y comprobar directamente en la base remota el resultado y los objetos creados. Si falla la conexión o la migración, informar el fallo y las pendientes sin afirmar que se aplicaron. `npm run db:init` actualiza solo LocalDB y nunca cuenta como migración desplegada.
3. Crear un commit con un mensaje claro en español.
4. Solo cuando el backend haya sido modificado, después del commit ejecutar `npm run publish:manual` para dejar exclusivamente el backend compilado en la carpeta local ignorada `publish/`. Los cambios limitados a frontend, documentación o configuración no deben recompilar ni reemplazar `publish/`.
5. Hacer `push` de los commits a la rama remota correspondiente.
6. Informar el hash del commit, las migraciones aplicadas y verificadas en remoto (y cualquier pendiente por un fallo), las validaciones realizadas, el resultado del `push` y, únicamente si cambió el backend, la ubicación del backend publicado.

No incluir secretos ni bases de datos locales en el commit o en `publish/`. Nunca afirmar que producción fue migrada basándose en LocalDB.
