/* Corrección puntual autorizada de MKM11928 (empresa 3, documento 52).
   NO es migración ni rutina de reenvío. Exige los importes y estados observados.
   No toca inventario, XML original, fechas, proveedor ni base externa Zeus.
   Solo permite cartera sin pagos/aplicaciones y envío sin intentos ni snapshot.
   Registra antes/después; si cualquier condición cambia, revierte todo.
   El llamador debe verificar servidor/base antes de ejecutar este archivo.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_WARNINGS ON;
SET ANSI_PADDING ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
IF @@TRANCOUNT<>0 THROW 52095,'Ejecute sin otra transaccion abierta.',1;
DECLARE @Previous sql_variant=SESSION_CONTEXT(N'BypassRls');
BEGIN TRY
 EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
 BEGIN TRANSACTION;
 DECLARE @Xml xml,@RawXml nvarchar(max),@Total decimal(20,4),@PayableId bigint,@Receipt bigint,@Before nvarchar(max);
 IF NOT EXISTS(SELECT 1 FROM core.Empresa WHERE EmpresaId=3 AND Codigo='01' AND RazonSocial='MOTOCENTRO SA')
   THROW 52095,'No coincide la empresa de la correccion.',1;
 SELECT @RawXml=XmlOriginal,@Total=TotalPagar FROM comp.DocumentoProveedor WITH(UPDLOCK,HOLDLOCK)
 WHERE EmpresaId=3 AND DocumentoProveedorId=52 AND NumeroDocumento='MKM11928' AND Estado='CONTABILIZADO'
   AND ImpuestoTotal=6602651.43 AND CargoTotal=0 AND DescuentoTotal=0;
 -- SQL recibe nvarchar: quitar solo la declaración de codificación, no alterar el XML guardado.
 IF LEFT(@RawXml,5)='<?xml' SET @RawXml=SUBSTRING(@RawXml,CHARINDEX('?>',@RawXml)+2,LEN(@RawXml));
 SET @Xml=TRY_CONVERT(xml,@RawXml);
 IF @Xml IS NULL THROW 52095,'No coincide la factura o falta el XML.',1;
 IF @Xml.exist('/*[local-name()="AttachedDocument"]')=1
 BEGIN
   DECLARE @Embedded nvarchar(max)=@Xml.value('(/*[local-name()="AttachedDocument"]/*[local-name()="Attachment"]/*[local-name()="ExternalReference"]/*[local-name()="Description"]/text())[1]','nvarchar(max)');
   IF LEFT(@Embedded,5)='<?xml' SET @Embedded=SUBSTRING(@Embedded,CHARINDEX('?>',@Embedded)+2,LEN(@Embedded));
   SET @Xml=TRY_CONVERT(xml,@Embedded);
 END;
 IF @Xml IS NULL OR @Xml.value('(/*[local-name()="Invoice"]/*[local-name()="ID"]/text())[1]','nvarchar(50)')<>'MKM11928'
   OR @Xml.value('(/*[local-name()="Invoice"]/*[local-name()="LegalMonetaryTotal"]/*[local-name()="TaxInclusiveAmount"]/text())[1]','decimal(20,4)')<>41353448.43
   OR @Xml.value('(/*[local-name()="Invoice"]/*[local-name()="WithholdingTaxTotal"]/*[local-name()="TaxSubtotal"]/*[local-name()="TaxAmount"]/text())[1]','decimal(20,4)')<>868769.93
   OR @Xml.value('(/*[local-name()="Invoice"]/*[local-name()="WithholdingTaxTotal"]/*[local-name()="TaxSubtotal"]/*[local-name()="TaxCategory"]/*[local-name()="Percent"]/text())[1]','decimal(10,4)')<>2.5
   THROW 52095,'El XML no respalda los importes de la correccion.',1;
 SELECT @Receipt=RecepcionMercanciaId FROM inv.RecepcionMercancia WITH(UPDLOCK,HOLDLOCK)
 WHERE EmpresaId=3 AND DocumentoProveedorId=52 AND Estado='CONTABILIZADA';
 IF @Receipt<>37 OR @Receipt IS NULL OR (SELECT COUNT(*) FROM inv.RecepcionMercancia WHERE EmpresaId=3 AND DocumentoProveedorId=52)<>1
   THROW 52095,'La entrada no coincide.',1;
 IF NOT EXISTS(SELECT 1 FROM core.ZeusEnvio WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=3 AND RecepcionMercanciaId=@Receipt AND Estado='REQUIERE_REVISION' AND Intentos=0 AND Snapshot IS NULL AND Documento IS NULL AND Fuente IS NULL)
   THROW 52095,'El envio Zeus cambio: no corregir ni reenviar automaticamente.',1;
 SELECT @PayableId=DocumentoPorPagarId FROM cxp.DocumentoPorPagar WITH(UPDLOCK,HOLDLOCK)
 WHERE EmpresaId=3 AND DocumentoProveedorId=52 AND Estado='ABIERTA' AND ValorOriginal=SaldoPendiente;
 IF @PayableId IS NULL OR (SELECT COUNT(*) FROM cxp.MovimientoProveedor WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=3 AND DocumentoPorPagarId=@PayableId)<>1
   OR NOT EXISTS(SELECT 1 FROM cxp.MovimientoProveedor WHERE EmpresaId=3 AND DocumentoPorPagarId=@PayableId AND TipoMovimiento='FACTURA' AND Abono=0 AND Cargo=@Total)
   THROW 52095,'Hay pagos/aplicaciones o la cartera no coincide. Se requiere conciliacion.',1;
 DECLARE @Lines TABLE(Id bigint PRIMARY KEY,Numero int,Antes decimal(20,4),Despues decimal(20,4));
 INSERT @Lines SELECT DocumentoProveedorLineaId,NumeroLinea,Retencion,FLOOR(Retencion*100)/100
 FROM comp.DocumentoProveedorLinea WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=3 AND DocumentoProveedorId=52;
 IF (SELECT COUNT(*) FROM @Lines)<>3 THROW 52095,'Cambio el numero de lineas.',1;
 IF @Total=40484678.50 AND (SELECT SUM(Antes) FROM @Lines)=868769.93
   AND EXISTS(SELECT 1 FROM cxp.DocumentoPorPagar WHERE DocumentoPorPagarId=@PayableId AND EmpresaId=3 AND ValorOriginal=@Total)
 BEGIN
   ROLLBACK; EXEC sys.sp_set_session_context @key=N'BypassRls',@value=@Previous;
   PRINT 'La correccion ya fue aplicada. No se modifico nada.'; RETURN;
 END;
 IF @Total<>41353448.43 OR (SELECT SUM(Antes) FROM @Lines)<>868769.9301
   OR NOT EXISTS(SELECT 1 FROM cxp.DocumentoPorPagar WHERE DocumentoPorPagarId=@PayableId AND EmpresaId=3 AND ValorOriginal=@Total)
   THROW 52095,'Los valores cambiaron; no se aplica una correccion a ciegas.',1;
 DECLARE @Cents int=CONVERT(int,ROUND((868769.93-(SELECT SUM(Despues) FROM @Lines))*100,0));
 IF @Cents<0 OR @Cents>3 THROW 52095,'No se puede distribuir el residuo.',1;
 ;WITH ordered AS(SELECT *,ROW_NUMBER() OVER(ORDER BY Antes-Despues DESC,Numero,Id) Position FROM @Lines)
 UPDATE ordered SET Despues=Despues+CASE WHEN Position<=@Cents THEN 0.01 ELSE 0 END;
 SELECT @Before=(SELECT @Total totalPagar,(SELECT Id,Numero,Antes FROM @Lines FOR JSON PATH) retenciones FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 UPDATE l SET Retencion=x.Despues FROM comp.DocumentoProveedorLinea l JOIN @Lines x ON x.Id=l.DocumentoProveedorLineaId WHERE l.EmpresaId=3 AND l.DocumentoProveedorId=52;
 UPDATE comp.DocumentoProveedor SET TotalPagar=40484678.50 WHERE EmpresaId=3 AND DocumentoProveedorId=52;
 UPDATE cxp.DocumentoPorPagar SET ValorOriginal=40484678.50,SaldoPendiente=40484678.50,ActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=3 AND DocumentoPorPagarId=@PayableId;
 -- Reparacion administrativa del cargo original erróneo, solo sin movimientos posteriores.
 -- BypassRls permite esta corrección excepcional; se conserva su ID y queda auditada.
 UPDATE cxp.MovimientoProveedor SET Cargo=40484678.50 WHERE EmpresaId=3 AND DocumentoPorPagarId=@PayableId AND TipoMovimiento='FACTURA';
 INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,Motivo,ValoresAnteriores,ValoresPosteriores,AplicacionOrigen)
 VALUES(3,NULL,'CORRECCION_RETENCION_XML','comp.DocumentoProveedor','52',N'Correccion autorizada MKM11928: descontar retencion XML y distribuir centavos sin residuo; sin pagos ni intentos Zeus.',@Before,
 N'{"totalPagar":40484678.50,"retencion":868769.93,"inventarioModificado":false,"reenviadoZeus":false}','SCRIPT_ADMINISTRATIVO');
 UPDATE core.ZeusEnvio SET Error=N'Retencion y neto corregidos con auditoria. Verifica la factura en Zeus antes de solicitar el envio.',ActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=3 AND RecepcionMercanciaId=@Receipt;
 IF (SELECT SUM(Retencion) FROM comp.DocumentoProveedorLinea WHERE EmpresaId=3 AND DocumentoProveedorId=52)<>868769.93
   THROW 52095,'No cuadra la retencion corregida.',1;
 COMMIT;
 EXEC sys.sp_set_session_context @key=N'BypassRls',@value=@Previous;
 PRINT 'MKM11928 corregida en ERP y cartera; no se envio a Zeus.';
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 EXEC sys.sp_set_session_context @key=N'BypassRls',@value=@Previous;
 THROW;
END CATCH;
