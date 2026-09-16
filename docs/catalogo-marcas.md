# Reconocimiento de marcas por empresa

Desde la migración 047 se consulta primero la referencia/código exacto dentro de la empresa. Si existe y está confirmada con marca activa, se usa esa marca aunque la descripción venga abreviada. Si el código no existe o no se envió, se conserva la comparación de descripción normalizada. Un código existente pero pendiente o inactivo no recurre a otra marca por descripción. No se convierten códigos a números ni se eliminan ceros iniciales. La misma regla se aplica al maestro de artículos. El endpoint admite peticiones anteriores sin códigos.

La migración 046 agrega `inv.Marca`, un maestro único por empresa vinculado a las referencias importadas. En **Datos maestros → Marcas** se pueden crear y editar nombres, activar/desactivar y consultar cuántas referencias tiene cada marca. Crear una marca sin referencias no permite inferir qué descripciones le corresponden. Las marcas dudosas del archivo permanecen pendientes, sin convertirlas en marcas confirmadas.

Al leer un XML, las tablas de clasificación y homologación muestran **Marca**, consultada por descripción directamente en SQL antes de crear artículos. La consulta es por lotes, conserva el orden de líneas y no reutiliza resultados entre empresas. Las marcas desactivadas, referencias ambiguas o textos sin coincidencia muestran **Sin reconocer**; un fallo de API muestra un error de consulta con opción de reintentar. La marca presentada no modifica el XML original ni guarda una instantánea histórica de la factura.

La migración 045 crea `inv.CatalogoMarcaDescripcion`, protegida por RLS. Guarda referencia, descripción, marca, línea, categoría y procedencia (archivo, SHA-256 y fila). No importa precios, existencias ni crea artículos.

`inv.fn_MarcaPorDescripcion` compara la descripción completa sin distinguir mayúsculas, tildes ni espacios repetidos. Conserva números y puntuación: no realiza coincidencias aproximadas. Si hay marcas contradictorias o alguna referencia pendiente para esa descripción, devuelve NULL. Referencias repetidas con la misma descripción/marca no generan ambigüedad.

El maestro consulta el catálogo en SQL al leer los artículos y muestra **Marca reconocida**. Aplica tanto a artículos nuevos creados desde XML como a los existentes que coincidan; no sobrescribe descripciones ni homologaciones. Cambiar una descripción o corregir el catálogo se refleja en la siguiente consulta. Esta marca es una clasificación consultada, no una instantánea histórica de la factura.

## Importación privada

Ejecutar `scripts/import-brand-catalog.ps1` con `-Workbook`, `-Python` (con openpyxl), `-EmpresaId`, `-ExpectedNit` y `-ExpectedDatabase`. Lee la conexión privada de `.env`, verifica base y empresa, valida todo el Excel antes de escribir e importa dentro de una transacción. Repetir la carga actualiza las mismas referencias sin duplicarlas; no elimina referencias ausentes. Los datos del cliente y el Excel no se incluyen en Git ni en publish.

Las etiquetas HAEB y HCEB se conservan literalmente y se dejan deshabilitadas para reconocimiento hasta que el propietario confirme su corrección. No se reemplazan por una marca supuesta.

Validación: `tests/brand-catalog.sql` se ejecuta únicamente en una base de pruebas y revierte sus datos; la prueba API verifica la marca de un artículo creado desde XML. Tras aplicar la migración remota y cargar el catálogo, desplegar manualmente el backend de `publish/` para habilitar el campo en la API.
