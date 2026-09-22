-- Correccion puntual autorizada de MKM11928. No es una migracion general.
-- Ejecutar con parametro bit @Confirmar: 0 valida y revierte; 1 confirma.
-- No envia a Zeus, no cambia XML ni inventario, no reescribe movimientos historicos.
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
IF DB_NAME()<>'ERPMontelibano' THROW 51970,'Base no autorizada para esta correccion.',1;
EXEC sys.sp_set_session_context @key=N'EmpresaId',@value=3;
BEGIN TRY
    BEGIN TRANSACTION;
    IF NOT EXISTS(SELECT 1 FROM comp.DocumentoProveedor WITH(UPDLOCK,HOLDLOCK)
        WHERE EmpresaId=3 AND DocumentoProveedorId=51 AND NumeroDocumento='MKM11928' AND TerceroId=19
          AND Estado='CONTABILIZADO' AND Moneda='COP' AND TotalPagar=41353448.43 AND ImpuestoTotal=6602651.43)
        THROW 51970,'La factura no coincide con el estado revisado o ya fue corregida.',1;
    IF NOT EXISTS(SELECT 1 FROM core.ZeusEnvio WITH(UPDLOCK,HOLDLOCK)
        WHERE EmpresaId=3 AND RecepcionMercanciaId=36 AND ZeusEnvioId=4 AND Estado='REQUIERE_REVISION'
          AND Intentos=0 AND Snapshot IS NULL AND Documento IS NULL AND Fuente IS NULL)
        THROW 51970,'El envio Zeus cambio; no se puede corregir automaticamente.',1;
    IF NOT EXISTS(SELECT 1 FROM inv.RecepcionMercancia WITH(UPDLOCK,HOLDLOCK)
        WHERE EmpresaId=3 AND RecepcionMercanciaId=36 AND DocumentoProveedorId=51 AND Estado='CONTABILIZADA')
        THROW 51970,'La entrada cambio de estado.',1;
    IF (SELECT COUNT(*) FROM comp.DocumentoProveedorLinea WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=3 AND DocumentoProveedorId=51)<>3
       OR (SELECT COUNT(*) FROM comp.DocumentoProveedorLinea WHERE EmpresaId=3 AND DocumentoProveedorId=51
             AND DocumentoProveedorLineaId IN(181,182,183) AND NumeroLinea IN(1,2,3)
             AND TotalNeto=11583599 AND Impuesto=2200883.81 AND Retencion=289589.9767)<>3
        THROW 51970,'Las lineas no coinciden con los importes revisados.',1;
    IF NOT EXISTS(SELECT 1 FROM cxp.DocumentoPorPagar WITH(UPDLOCK,HOLDLOCK)
        WHERE EmpresaId=3 AND DocumentoPorPagarId=13 AND DocumentoProveedorId=51 AND Estado='ABIERTA'
          AND ValorOriginal=41353448.43 AND SaldoPendiente=41353448.43)
        THROW 51970,'La cartera cambio o tiene aplicaciones.',1;
    IF (SELECT COUNT(*) FROM cxp.MovimientoProveedor WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=3 AND DocumentoPorPagarId=13)<>1
       OR NOT EXISTS(SELECT 1 FROM cxp.MovimientoProveedor WHERE EmpresaId=3 AND DocumentoPorPagarId=13
           AND TipoMovimiento='FACTURA' AND Cargo=41353448.43 AND Abono=0)
        THROW 51970,'Existen pagos o movimientos posteriores: se cancela la correccion.',1;

    DECLARE @Antes nvarchar(max)=(SELECT
        JSON_QUERY((SELECT TotalPagar FROM comp.DocumentoProveedor WHERE EmpresaId=3 AND DocumentoProveedorId=51 FOR JSON PATH)) Factura,
        JSON_QUERY((SELECT DocumentoProveedorLineaId,NumeroLinea,Retencion FROM comp.DocumentoProveedorLinea WHERE EmpresaId=3 AND DocumentoProveedorId=51 ORDER BY NumeroLinea FOR JSON PATH)) Lineas,
        JSON_QUERY((SELECT ValorOriginal,SaldoPendiente,Estado FROM cxp.DocumentoPorPagar WHERE EmpresaId=3 AND DocumentoPorPagarId=13 FOR JSON PATH)) Cartera
        FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);

    UPDATE comp.DocumentoProveedorLinea SET Retencion=CASE WHEN NumeroLinea=3 THEN 289589.97 ELSE 289589.98 END
        WHERE EmpresaId=3 AND DocumentoProveedorId=51;
    UPDATE comp.DocumentoProveedor SET TotalPagar=40484678.50 WHERE EmpresaId=3 AND DocumentoProveedorId=51;
    UPDATE cxp.DocumentoPorPagar SET ValorOriginal=40484678.50,SaldoPendiente=40484678.50,ActualizadoEnUtc=SYSUTCDATETIME()
        WHERE EmpresaId=3 AND DocumentoPorPagarId=13;
    -- Reverso parcial por retencion omitida, no pago, sin alterar el cargo original.
    INSERT cxp.MovimientoProveedor(EmpresaId,TerceroId,DocumentoPorPagarId,TipoMovimiento,FechaMovimiento,FechaVencimiento,
        NumeroDocumento,Moneda,Cargo,Abono,TipoDocumentoOrigen,DocumentoOrigenId)
    SELECT EmpresaId,TerceroId,DocumentoPorPagarId,'REVERSO',FechaReconocimiento,FechaVencimiento,
        'AJ-RET-MKM11928',Moneda,0,868769.93,'CORRECCION_RETENCION',51
    FROM cxp.DocumentoPorPagar WHERE EmpresaId=3 AND DocumentoPorPagarId=13;

    IF (SELECT SUM(Retencion) FROM comp.DocumentoProveedorLinea WHERE EmpresaId=3 AND DocumentoProveedorId=51)<>868769.93
       OR (SELECT SUM(TotalNeto+Impuesto-Retencion) FROM comp.DocumentoProveedorLinea WHERE EmpresaId=3 AND DocumentoProveedorId=51)<>40484678.50
       OR (SELECT SUM(Cargo-Abono) FROM cxp.MovimientoProveedor WHERE EmpresaId=3 AND DocumentoPorPagarId=13)<>40484678.50
        THROW 51970,'La correccion no cuadra; se revierte completamente.',1;

    DECLARE @Despues nvarchar(max)=(SELECT
        JSON_QUERY((SELECT TotalPagar FROM comp.DocumentoProveedor WHERE EmpresaId=3 AND DocumentoProveedorId=51 FOR JSON PATH)) Factura,
        JSON_QUERY((SELECT DocumentoProveedorLineaId,NumeroLinea,Retencion FROM comp.DocumentoProveedorLinea WHERE EmpresaId=3 AND DocumentoProveedorId=51 ORDER BY NumeroLinea FOR JSON PATH)) Lineas,
        JSON_QUERY((SELECT ValorOriginal,SaldoPendiente,Estado FROM cxp.DocumentoPorPagar WHERE EmpresaId=3 AND DocumentoPorPagarId=13 FOR JSON PATH)) Cartera,
        JSON_QUERY((SELECT TipoMovimiento,NumeroDocumento,Cargo,Abono FROM cxp.MovimientoProveedor WHERE EmpresaId=3 AND DocumentoPorPagarId=13 FOR JSON PATH)) Movimientos
        FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
    INSERT audit.Evento(EmpresaId,Operacion,Entidad,EntidadId,DocumentoNumero,Motivo,ValoresAnteriores,ValoresPosteriores,AplicacionOrigen)
    VALUES(3,'CORREGIR_RETENCION_MKM11928','comp.DocumentoProveedor','51','MKM11928',
        N'Correccion de soporte autorizada expresamente por el propietario en la tarea: retencion XML 868769.93, distribucion exacta en centavos y cartera neta; sin pagos ni intentos Zeus. Se conserva movimiento original con reverso parcial identificado.',
        @Antes,@Despues,'SOPORTE_AUTORIZADO');
    DECLARE @Auditoria bigint=SCOPE_IDENTITY();
    UPDATE core.ZeusEnvio SET Error=N'Retencion y cartera corregidas con auditoria. Reenvia desde Envios pendientes; no repitas la contabilizacion ERP.',ActualizadoEnUtc=SYSUTCDATETIME()
        WHERE EmpresaId=3 AND ZeusEnvioId=4 AND Estado='REQUIERE_REVISION' AND Intentos=0;
    IF @Confirmar=1 COMMIT; ELSE ROLLBACK;
    SELECT @Confirmar Confirmado,@Auditoria Auditoria,@Antes Antes,@Despues Despues;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT>0 ROLLBACK;
    THROW;
END CATCH;
