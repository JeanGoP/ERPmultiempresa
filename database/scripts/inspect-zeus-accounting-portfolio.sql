/*
  Inspección de cartera histórica Zeus para Nexo.
  Solo consulta metadatos y estadísticas limitadas; no modifica información.
  Ejecutar en la base contable Zeus de una empresa y compartir todas las cuadrículas.
*/
SET NOCOUNT ON;

SELECT @@SERVERNAME AS Servidor, DB_NAME() AS BaseActual;

SELECT SCHEMA_NAME(o.schema_id) AS Esquema,o.name AS Tabla,
       c.column_id AS Orden,c.name AS Columna,TYPE_NAME(c.user_type_id) AS Tipo,
       c.max_length AS Longitud,c.precision AS Precision,c.scale AS Escala,c.is_nullable AS PermiteNull
FROM sys.objects o
JOIN sys.columns c ON c.object_id=o.object_id
WHERE o.type='U' AND SCHEMA_NAME(o.schema_id)='dbo'
  AND o.name IN ('TRANSAC','DOCUMENT','Facturas_Bu','Facturas','MAECONT','TERCEROS','CLIENTES','PROVEEDORES')
ORDER BY o.name,c.column_id;

SELECT t.name AS Tabla,i.name AS Indice,i.is_unique AS EsUnico,
       ic.key_ordinal AS Orden,c.name AS Columna
FROM sys.tables t
JOIN sys.indexes i ON i.object_id=t.object_id AND i.is_hypothetical=0
JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id AND ic.key_ordinal>0
JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
WHERE SCHEMA_NAME(t.schema_id)='dbo' AND t.name IN ('TRANSAC','Facturas_Bu','Facturas')
ORDER BY t.name,i.name,ic.key_ordinal;

SELECT tr.name AS TriggerNombre,t.name AS Tabla,tr.is_disabled AS Deshabilitado,
       CASE WHEN OBJECT_DEFINITION(tr.object_id) IS NULL THEN 1 ELSE 0 END AS DefinicionNoVisible
FROM sys.triggers tr
JOIN sys.tables t ON t.object_id=tr.parent_id
WHERE SCHEMA_NAME(t.schema_id)='dbo' AND t.name IN ('TRANSAC','DOCUMENT','Facturas_Bu','Facturas')
ORDER BY t.name,tr.name;

SELECT p.name AS Procedimiento,
       CASE WHEN OBJECT_DEFINITION(p.object_id) IS NULL THEN 1 ELSE 0 END AS DefinicionNoVisible
FROM sys.procedures p
WHERE SCHEMA_NAME(p.schema_id)='dbo'
  AND (p.name LIKE '%Cartera%' OR p.name LIKE '%Factura%' OR p.name LIKE '%Contabilidad%')
ORDER BY p.name;
