# Registro de compras

Módulo ERP para registrar compras de proveedores. Procesa XML de la DIAN, entradas manuales de mercancía y causaciones de servicios. Una factura puede combinar mercancías, servicios y costos adicionales manteniendo separado el efecto de cada línea.

## Lector web actual

Requiere Node.js 18 o superior.

Copia `.env.example` como `.env` y configura `ConnectionStrings__NexoErp`. La API carga ese archivo al iniciar y da prioridad a las variables ya definidas por el sistema operativo. El `.env` real está ignorado por Git.

```powershell
npm start
```

Abre <http://127.0.0.1:4173> e inicia también la API local en el puerto `5180`. La interfaz trabaja exclusivamente contra la API ERP, permite elegir la empresa y abrir Entrada automática, Entrada manual o Causación de servicios. La lectura UBL 2.1, incluido `AttachedDocument` con `CDATA`, extrae proveedor, fechas, artículos, descuentos, impuestos, fletes, motor, chasis, VIN y seriales.

Tanto la entrada automática como la entrada manual crean el documento como borrador y separan sus efectos. La mercancía prepara una recepción y solo contabiliza Kardex después de una confirmación explícita; los servicios generan una causación independiente con cuentas, centro de costo, proyecto, impuestos, retenciones, comprobante balanceado y cuenta por pagar, siempre sin afectar Kardex.

La interfaz ofrece **Guardar solo como borrador** y **Guardar y contabilizar entrada**. La segunda opción ejecuta el registro, preparación y contabilización de mercancía en una sola acción confirmada. **Compras → Entradas guardadas** permite recuperar documentos después de cerrar la sesión, buscar por factura, proveedor, motor, chasis o VIN, revisar todos los seriales desde el borrador, contabilizar pendientes y anular borradores que todavía no tengan procesos preparados.

El menú **Administración → Usuarios y permisos** permite crear usuarios, activar o suspender su acceso por empresa, asignar uno o varios roles y restablecer contraseñas. El superadministrador también puede crear roles y seleccionar sus permisos operativos.

El rol **Auxiliar de bodega** permite trabajar en **Inventario → Recepción física**. Allí el usuario ve las recepciones de mercancía preparadas y pendientes de Kardex, marca cada moto como recibida conforme, recibida con novedad o no recibida, conserva observaciones por unidad y puede contabilizar la recepción para ingresar la mercancía a la bodega. Las marcas físicas son historial operativo; no bloquean la contabilización.

Al crear una empresa, el sistema deja preparados automáticamente la unidad `UND`, la bodega principal `PPL` y los períodos contable y de inventario del mes actual. Para una empresa creada antes de esta mejora, el superadministrador puede abrir una factura con mercancía y usar **Preparar empresa ahora**; después se habilitan los selectores de bodega y período.

## Núcleo SQL Server

```powershell
npm run db:init
npm run db:check
```

Los comandos crean `NexoErpDev` en SQL Server LocalDB, aplican 43 migraciones idempotentes y prueban costos, inventario, compras, causaciones, cartera de proveedores, maestros, homologación, seguridad, auditoría y operación productiva.

La estrategia de códigos `MOT-`/`ART-`, equivalencias por proveedor y seriales está documentada en [docs/codificacion-articulos.md](docs/codificacion-articulos.md).

## API

```powershell
dotnet run --project backend/NexoERP.Api
```

La API exige autenticación salvo en `/api/v1/health` y `/api/v1/auth/login`. Para habilitar un administrador local después de crear la empresa:

```powershell
powershell -File database/scripts/set-local-user.ps1 -Correo admin@empresa.com -Password (Read-Host -AsSecureString) -NombreCompleto "Administrador" -EmpresaCodigo EMPRESA
```

La prueba HTTP aislada crea una base temporal, aplica las 43 migraciones y valida autenticación, empresa, permisos, maestros, homologación, recepción, gestión de novedades, causación, cartera de proveedores y salud operativa sin modificar `NexoErpDev`:

```powershell
npm run api:smoke
```

Consulta [docs/api.md](docs/api.md) para ver las rutas y los permisos publicados.

Para preparación productiva consulta el [manual operativo](docs/operations-manual.md), la [matriz de permisos](docs/permissions-matrix.md) y el [acta de autorización](docs/go-live-approval.md). El ensayo integral se ejecuta con `npm run production:rehearsal`.

La aplicación trabaja siempre con la API y muestra únicamente las empresas autorizadas para el usuario. La homologación del XML usa los artículos reales de la empresa.

Consulta [docs/implementation-status.md](docs/implementation-status.md) para el avance y los pendientes.

## Despliegue del frontend en Netlify

El repositorio incluye `netlify.toml`, por lo que Netlify puede desplegarlo sin configurar manualmente el comando de construcción ni el directorio de publicación.

1. Importa `JeanGoP/ERPmultiempresa` desde Netlify.
2. Selecciona la rama `main`.
3. Conserva la configuración detectada y ejecuta el despliegue.

La configuración ejecuta las validaciones JavaScript, publica `public/`, conserva las rutas de la SPA y envía `/erp-api/*` al backend alojado en `http://stecno.dyndns.org/ERP`.

Después del despliegue, comprueba `https://TU-SITIO.netlify.app/erp-api/api/v1/health`. Debe responder con `status: ok`, `database: connected` y `migrations: 43`.

> Seguridad pendiente: habilitar HTTPS en el backend y actualizar el destino del proxy en `netlify.toml`. La exportación a Excel no forma parte de esta configuración de Netlify.

## Paquete para publicación manual

Después de validar y crear el commit del trabajo, genera una entrega completa con:

```powershell
npm run publish:manual
```

El comando reemplaza de forma segura la carpeta local `publish/` y deja allí exclusivamente el backend compilado en configuración Release, sin copiar `appsettings.json` ni `.env`. Transfiere el `.env` de manera segura y separada, y déjalo junto al ejecutable del backend en el servidor. Consulta [docs/manual-publishing.md](docs/manual-publishing.md) para el orden de despliegue.
