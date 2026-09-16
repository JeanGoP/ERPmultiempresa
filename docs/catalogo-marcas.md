# Reconocimiento de marcas por empresa

La migración 045 crea `inv.CatalogoMarcaDescripcion`, protegida por RLS. Guarda referencia, descripción, marca, línea, categoría y procedencia (archivo, SHA-256 y fila). No importa precios, existencias ni crea artículos.

`inv.fn_MarcaPorDescripcion` compara la descripción completa sin distinguir mayúsculas, tildes ni espacios repetidos. Conserva números y puntuación: no realiza coincidencias aproximadas. Si hay marcas contradictorias o alguna referencia pendiente para esa descripción, devuelve NULL. Referencias repetidas con la misma descripción/marca no generan ambigüedad.

El maestro consulta el catálogo en SQL al leer los artículos y muestra **Marca reconocida**. Aplica tanto a artículos nuevos creados desde XML como a los existentes que coincidan; no sobrescribe descripciones ni homologaciones. Cambiar una descripción o corregir el catálogo se refleja en la siguiente consulta. Esta marca es una clasificación consultada, no una instantánea histórica de la factura.

## Importación privada

Ejecutar `scripts/import-brand-catalog.ps1` con `-Workbook`, `-Python` (con openpyxl), `-EmpresaId`, `-ExpectedNit` y `-ExpectedDatabase`. Lee la conexión privada de `.env`, verifica base y empresa, valida todo el Excel antes de escribir e importa dentro de una transacción. Repetir la carga actualiza las mismas referencias sin duplicarlas; no elimina referencias ausentes. Los datos del cliente y el Excel no se incluyen en Git ni en publish.

Las etiquetas HAEB y HCEB se conservan literalmente y se dejan deshabilitadas para reconocimiento hasta que el propietario confirme su corrección. No se reemplazan por una marca supuesta.

Validación: `tests/brand-catalog.sql` se ejecuta únicamente en una base de pruebas y revierte sus datos; la prueba API verifica la marca de un artículo creado desde XML. Tras aplicar la migración remota y cargar el catálogo, desplegar manualmente el backend de `publish/` para habilitar el campo en la API.
