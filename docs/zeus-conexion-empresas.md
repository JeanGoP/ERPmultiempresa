# Conexión Zeus por empresa

Seguridad → Empresas → Nueva empresa / Editar → Conexión Zeus. Solo el superadministrador puede consultar o cambiar estos datos. Crear una empresa sin Zeus sigue permitido.

El usuario SQL autentica la conexión. El usuario contable es el que reciben los procedimientos de Zeus. La prueba hace consultas de lectura; no contabiliza ni crea terceros. La contraseña vacía al editar conserva la anterior; cambiar servidor, base o usuario SQL exige escribirla. Un cambio de destino deshabilita los envíos automáticos hasta revisar la configuración contable. Los envíos pendientes, en curso o inciertos bloquean cambios de conexión.

La migración 057 agrega `core.ZeusConexion`. Las conexiones existentes `Zeus__Companies__ID__ConnectionString` siguen siendo el respaldo mientras no haya una conexión guardada en el maestro. Las credenciales guardadas tienen prioridad. No se copian secretos en migraciones, respuestas HTTP, auditoría, snapshots ni paquetes publicados.

## Claves de cifrado del backend

ASP.NET Data Protection cifra cada contraseña con un propósito ligado a su EmpresaId. Las claves se guardan fuera de publish, en `LocalApplicationData/NexoERP/ZeusKeys` del usuario que ejecuta la API. En Windows se protegen además con DPAPI de ese usuario. Opcionalmente configure `Zeus__KeyRingPath` con una ruta persistente privada fuera del directorio publicado.

Respaldar esa carpeta junto con la base. Mantener identidad y permisos del servicio entre despliegues. En contenedores Linux montar un volumen persistente privado y configurar la ruta; las claves en disco requieren protección del volumen y permisos restringidos. No incluirlas en Git ni publish. Para varias instancias deben compartir un mecanismo de claves compatible. Perder las claves, cambiar la identidad Windows o moverlas a otra máquina puede exigir volver a introducir las contraseñas; no se recurre silenciosamente al .env si una credencial guardada no se puede descifrar.

Desplegar la migración antes del nuevo backend. La migración no modifica la base externa Zeus ni habilita envíos.
