# Instrucciones del proyecto

Al terminar cada trabajo de implementación:

1. Ejecutar las validaciones proporcionales al cambio y corregir sus errores.
2. Las migraciones del entorno desplegado las ejecuta manualmente el propietario del proyecto. Informar claramente si el trabajo agrega migraciones pendientes, pero no bloquear por ello el commit, la publicación ni el `push`. `npm run db:init` actualiza solo LocalDB y nunca cuenta como migración desplegada.
3. Crear un commit con un mensaje claro en español.
4. Después del commit, ejecutar `npm run publish:manual` para dejar exclusivamente el backend compilado en la carpeta local ignorada `publish/`.
5. Hacer `push` de los commits a la rama remota correspondiente.
6. Informar el hash del commit, las migraciones pendientes para ejecución manual, las validaciones realizadas, la ubicación del backend publicado y el resultado del `push`.

No incluir secretos ni bases de datos locales en el commit o en `publish/`. Nunca afirmar que producción fue migrada basándose en LocalDB.
