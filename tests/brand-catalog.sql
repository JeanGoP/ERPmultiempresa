SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
BEGIN TRANSACTION;
INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES('MARCAQA1','900888771',N'Prueba marcas 1');
DECLARE @A bigint=SCOPE_IDENTITY();
INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES('MARCAQA2','900888772',N'Prueba marcas 2');
DECLARE @B bigint=SCOPE_IDENTITY();
INSERT inv.CatalogoMarcaDescripcion(EmpresaId,Referencia,Descripcion,Marca,Habilitada,ArchivoOrigen,ArchivoSha256,FilaOrigen) VALUES
(@A,'1',N'Nevera frío 25','MARCA A',1,'qa',REPLICATE('0',64),2),
(@A,'2',N'Nevera frío 25','MARCA A',1,'qa',REPLICATE('0',64),3),
(@A,'3',N'Conflicto','MARCA A',1,'qa',REPLICATE('0',64),4),
(@A,'4',N'Conflicto','MARCA B',1,'qa',REPLICATE('0',64),5),
(@A,'5',N'Pendiente','HAEB',0,'qa',REPLICATE('0',64),6),
(@B,'1',N'Nevera frío 25','MARCA B',1,'qa',REPLICATE('0',64),2);
IF COALESCE((SELECT Marca FROM inv.fn_MarcaPorDescripcion(@A,N'  NEVERA   FRIO 25  ')),'')<>'MARCA A' THROW 51610,'Falla normalización o duplicados de igual marca.',1;
IF (SELECT Marca FROM inv.fn_MarcaPorDescripcion(@A,N'Nevera frío 250')) IS NOT NULL THROW 51611,'No debe inferir modelos similares.',1;
IF (SELECT Marca FROM inv.fn_MarcaPorDescripcion(@A,N'Conflicto')) IS NOT NULL THROW 51612,'No debe resolver marcas ambiguas.',1;
IF (SELECT Marca FROM inv.fn_MarcaPorDescripcion(@A,N'Pendiente')) IS NOT NULL THROW 51613,'No debe resolver marcas pendientes.',1;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=0;
EXEC sys.sp_set_session_context @key=N'EmpresaId',@value=@A;
IF EXISTS(SELECT 1 FROM inv.CatalogoMarcaDescripcion WHERE EmpresaId=@B) THROW 51614,'RLS no aísla el catálogo.',1;
IF (SELECT Marca FROM inv.fn_MarcaPorDescripcion(@B,N'Nevera frío 25')) IS NOT NULL THROW 51615,'La función filtra información de otra empresa.',1;
EXEC sys.sp_set_session_context @key=N'EmpresaId',@value=@B;
IF COALESCE((SELECT Marca FROM inv.fn_MarcaPorDescripcion(@B,N'Nevera frío 25')),'')<>'MARCA B' THROW 51616,'La marca debe depender de la empresa.',1;
ROLLBACK;
PRINT 'Catálogo: normalización, duplicados, ambigüedad, modelos distintos y aislamiento RLS correctos.';
