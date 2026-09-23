/* SOLO LECTURA. Ejecutar en la base de PRUEBAS DE ZEUS, no en el ERP.
   Compartir resultados con soporte. No crea comprobantes ni cambia saldos.
   Las definiciones NULL pueden indicar cifrado o falta de VIEW DEFINITION.
   No deshabilitar triggers ni dar permisos administrativos a la aplicación. */
SET NOCOUNT ON;
IF OBJECT_ID(N'dbo.DOCUMENT',N'U') IS NULL OR OBJECT_ID(N'dbo.TRANSAC',N'U') IS NULL
    THROW 52098,'No se identifico una base Zeus con DOCUMENT y TRANSAC.',1;
SELECT CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) Servidor,DB_NAME() BaseActual;
SELECT t.name TriggerNombre,OBJECT_SCHEMA_NAME(t.parent_id) Esquema,OBJECT_NAME(t.parent_id) Tabla,
       t.is_disabled Deshabilitado,OBJECTPROPERTY(t.object_id,'IsEncrypted') Cifrado,
       OBJECT_DEFINITION(t.object_id) Definicion
FROM sys.triggers t WHERE t.parent_id IN(OBJECT_ID('dbo.TRANSAC'),OBJECT_ID('dbo.DOCUMENT'));
SELECT OBJECT_NAME(d.referencing_id) TriggerNombre,d.referenced_schema_name EsquemaReferido,
       d.referenced_entity_name ObjetoReferido,o.type_desc Tipo,OBJECT_DEFINITION(o.object_id) Definicion
FROM sys.sql_expression_dependencies d
JOIN sys.triggers t ON t.object_id=d.referencing_id
LEFT JOIN sys.objects o ON o.object_id=d.referenced_id
WHERE t.parent_id IN(OBJECT_ID('dbo.TRANSAC'),OBJECT_ID('dbo.DOCUMENT'));
SELECT s.name Esquema,o.name Objeto,o.type_desc Tipo
FROM sys.objects o JOIN sys.schemas s ON s.schema_id=o.schema_id
WHERE o.is_ms_shipped=0 AND (o.name LIKE '%Egreso%' OR o.name LIKE '%Cartera%' OR o.name LIKE '%Abono%' OR o.name LIKE '%SaldoProv%')
ORDER BY o.type_desc,o.name;
SELECT OBJECT_NAME(c.object_id) Tabla,c.name Columna,TYPE_NAME(c.user_type_id) Tipo,c.max_length Longitud,c.is_nullable PermiteNull
FROM sys.columns c WHERE c.object_id IN(OBJECT_ID('dbo.FUENTES'),OBJECT_ID('dbo.BANCOS'),OBJECT_ID('dbo.MONEDAS'),OBJECT_ID('dbo.MAECONT'))
ORDER BY Tabla,c.column_id;
