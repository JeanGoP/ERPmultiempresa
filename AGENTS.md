# Instrucciones del proyecto

Al terminar cada trabajo de implementación:

1. Ejecutar las validaciones proporcionales al cambio y corregir sus errores.
2. Aplicar las migraciones nuevas a la base de datos configurada y verificar su resultado.
3. Crear un commit con un mensaje claro en español.
4. Después del commit, ejecutar `npm run publish:manual` para dejar exclusivamente el backend compilado en la carpeta local ignorada `publish/`.
5. Hacer `push` de los commits a la rama remota correspondiente.
6. Informar el hash del commit, las migraciones y validaciones realizadas, la ubicación del backend publicado y el resultado del `push`.

No incluir secretos ni bases de datos locales en el commit o en `publish/`.
