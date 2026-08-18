SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='013_landed_cost_application')
BEGIN
    BEGIN TRANSACTION;
    ALTER TABLE inv.MovimientoInventario DROP CONSTRAINT CK_MovimientoInventario_Cantidades;
    ALTER TABLE inv.MovimientoInventario ADD CONSTRAINT CK_MovimientoInventario_Cantidades CHECK
    (
        (CantidadEntrada>0 AND CantidadSalida=0) OR
        (CantidadSalida>0 AND CantidadEntrada=0) OR
        (TipoMovimiento='AJUSTE_COSTO' AND CantidadEntrada=0 AND CantidadSalida=0 AND ValorMovimiento>0)
    );
    ALTER TABLE cost.DistribucionCostoLinea ADD AplicacionIdempotencyKey uniqueidentifier NOT NULL CONSTRAINT DF_DistribucionLinea_AplicacionKey DEFAULT NEWID();
    EXEC(N'CREATE UNIQUE INDEX UX_DistribucionLinea_AplicacionKey ON cost.DistribucionCostoLinea(EmpresaId,AplicacionIdempotencyKey);');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('013_landed_cost_application',N'Capitalización previa y ajuste de valor seguro para costos adicionales tardíos');
    COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_AjustarValorInventario
    @EmpresaId bigint,@BodegaId bigint,@ArticuloId bigint,@PeriodoInventarioId bigint,@FechaMovimiento datetime2(7),@FechaContable date,
    @TipoDocumentoOrigen varchar(40),@DocumentoOrigenId bigint,@DocumentoLineaOrigenId bigint,@NumeroDocumento nvarchar(50),
    @ValorAjuste decimal(20,4),@IdempotencyKey uniqueidentifier,@UsuarioId bigint=NULL,@CorrelationId uniqueidentifier=NULL,@MovimientoRelacionadoId bigint=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @ValorAjuste<=0 THROW 51840,'El ajuste de valor debe ser mayor que cero.',1;
    DECLARE @Existente bigint=(SELECT MovimientoInventarioId FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND IdempotencyKey=@IdempotencyKey);
    IF @Existente IS NOT NULL
    BEGIN
        SELECT MovimientoInventarioId,ExistenciaPosterior,CostoPromedioPosterior,ValorTotalPosterior,CAST(1 AS bit) YaExistia FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND MovimientoInventarioId=@Existente;
        RETURN;
    END;
    BEGIN TRANSACTION;
    DECLARE @LockResult int,@LockResource nvarchar(255)=CONCAT(N'INV:',@EmpresaId,N':',@BodegaId,N':',@ArticuloId);
    EXEC @LockResult=sys.sp_getapplock @Resource=@LockResource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=15000;
    IF @LockResult<0 THROW 51841,'No fue posible bloquear el saldo para ajustar su valor.',1;
    IF NOT EXISTS(SELECT 1 FROM core.PeriodoInventario WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoInventarioId AND Estado IN('ABIERTO','REABIERTO') AND @FechaContable BETWEEN FechaInicio AND FechaFin)
        THROW 51842,'El periodo de inventario está cerrado o no corresponde a la fecha.',1;
    DECLARE @Existencia decimal(20,6),@ValorAnterior decimal(20,4),@CostoAnterior decimal(20,8);
    SELECT @Existencia=Existencia,@ValorAnterior=ValorTotal,@CostoAnterior=CostoPromedio FROM inv.SaldoArticuloBodega WITH(UPDLOCK,HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId;
    IF @Existencia IS NULL OR @Existencia<=0 THROW 51843,'No hay existencia positiva para capitalizar el costo adicional.',1;
    DECLARE @ValorPosterior decimal(20,4)=@ValorAnterior+@ValorAjuste;
    DECLARE @CostoPosterior decimal(20,8)=CAST(@ValorPosterior/@Existencia AS decimal(20,8));
    INSERT inv.MovimientoInventario(EmpresaId,IdempotencyKey,BodegaId,ArticuloId,PeriodoInventarioId,FechaMovimiento,FechaContable,TipoMovimiento,ModuloOrigen,TipoDocumentoOrigen,DocumentoOrigenId,DocumentoLineaOrigenId,NumeroDocumento,CantidadEntrada,CantidadSalida,ExistenciaAnterior,ExistenciaPosterior,CostoUnitarioAnterior,CostoUnitarioMovimiento,CostoPromedioPosterior,ValorMovimiento,ValorTotalAnterior,ValorTotalPosterior,MovimientoRelacionadoId,UsuarioId,CorrelationId)
    VALUES(@EmpresaId,@IdempotencyKey,@BodegaId,@ArticuloId,@PeriodoInventarioId,@FechaMovimiento,@FechaContable,'AJUSTE_COSTO','COSTOS',@TipoDocumentoOrigen,@DocumentoOrigenId,@DocumentoLineaOrigenId,@NumeroDocumento,0,0,@Existencia,@Existencia,@CostoAnterior,CAST(@ValorAjuste/@Existencia AS decimal(20,8)),@CostoPosterior,@ValorAjuste,@ValorAnterior,@ValorPosterior,@MovimientoRelacionadoId,@UsuarioId,@CorrelationId);
    DECLARE @MovimientoId bigint=SCOPE_IDENTITY();
    UPDATE inv.SaldoArticuloBodega SET ValorTotal=@ValorPosterior,CostoPromedio=@CostoPosterior,UltimoMovimientoId=@MovimientoId,ActualizadoEnUtc=SYSUTCDATETIME()
    WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresAnteriores,ValoresPosteriores,AplicacionOrigen,CorrelationId)
    VALUES(@EmpresaId,@UsuarioId,'INVENTARIO_AJUSTE_COSTO','inv.MovimientoInventario',CONVERT(nvarchar(100),@MovimientoId),@NumeroDocumento,
        CONCAT(N'{"valor":',@ValorAnterior,N',"costoPromedio":',@CostoAnterior,N'}'),CONCAT(N'{"valor":',@ValorPosterior,N',"costoPromedio":',@CostoPosterior,N'}'),'COSTOS',@CorrelationId);
    COMMIT;
    SELECT @MovimientoId MovimientoInventarioId,@Existencia ExistenciaPosterior,@CostoPosterior CostoPromedioPosterior,@ValorPosterior ValorTotalPosterior,CAST(0 AS bit) YaExistia;
END;
GO

CREATE OR ALTER PROCEDURE cost.usp_AplicarDistribucionCosto
    @EmpresaId bigint,@DistribucionCostoId bigint,@PeriodoInventarioId bigint=NULL,@FechaContable date=NULL,
    @UsuarioId bigint=NULL,@CorrelationId uniqueidentifier=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @CorrelationId IS NULL SET @CorrelationId=NEWID();
    BEGIN TRANSACTION;
    DECLARE @Estado varchar(20),@DocumentoCostoId bigint,@Numero nvarchar(50);
    SELECT @Estado=d.Estado,@DocumentoCostoId=d.DocumentoCostoId,@Numero=dc.NumeroSoporte FROM cost.DistribucionCosto d WITH(UPDLOCK,HOLDLOCK)
    JOIN cost.DocumentoCostoAdquisicion dc ON dc.EmpresaId=d.EmpresaId AND dc.DocumentoCostoId=d.DocumentoCostoId
    WHERE d.EmpresaId=@EmpresaId AND d.DistribucionCostoId=@DistribucionCostoId;
    IF @Estado IS NULL THROW 51850,'La distribución no existe o no pertenece a la empresa.',1;
    IF @Estado='APLICADA'
    BEGIN
        COMMIT;
        SELECT @DistribucionCostoId DistribucionCostoId,@Estado Estado,(SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='DISTRIBUCION_COSTO' AND DocumentoOrigenId=@DistribucionCostoId) AjustesKardex,CAST(1 AS bit) YaExistia;
        RETURN;
    END;
    IF @Estado NOT IN('CALCULADA','APROBADA') THROW 51851,'La distribución no puede aplicarse en su estado actual.',1;
    IF NOT EXISTS(SELECT 1 FROM cost.DistribucionCostoLinea WHERE EmpresaId=@EmpresaId AND DistribucionCostoId=@DistribucionCostoId) THROW 51852,'La distribución no ha sido calculada.',1;

    DECLARE @DistribucionLineaId bigint,@RecepcionLineaId bigint,@Valor decimal(20,4),@Key uniqueidentifier,@RecepcionId bigint,@RecepcionEstado varchar(15),
            @BodegaId bigint,@ArticuloId bigint,@MovimientoRecepcionId bigint;
    DECLARE @R TABLE(MovimientoInventarioId bigint,ExistenciaPosterior decimal(20,6),CostoPromedioPosterior decimal(20,8),ValorTotalPosterior decimal(20,4),YaExistia bit);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT dl.DistribucionCostoLineaId,dl.RecepcionMercanciaLineaId,dl.ValorAsignado,dl.AplicacionIdempotencyKey,r.RecepcionMercanciaId,h.Estado,h.BodegaId,r.ArticuloId
        FROM cost.DistribucionCostoLinea dl JOIN inv.RecepcionMercanciaLinea r ON r.EmpresaId=dl.EmpresaId AND r.RecepcionMercanciaLineaId=dl.RecepcionMercanciaLineaId
        JOIN inv.RecepcionMercancia h ON h.EmpresaId=r.EmpresaId AND h.RecepcionMercanciaId=r.RecepcionMercanciaId
        WHERE dl.EmpresaId=@EmpresaId AND dl.DistribucionCostoId=@DistribucionCostoId ORDER BY r.ArticuloId,dl.RecepcionMercanciaLineaId;
    OPEN c; FETCH NEXT FROM c INTO @DistribucionLineaId,@RecepcionLineaId,@Valor,@Key,@RecepcionId,@RecepcionEstado,@BodegaId,@ArticuloId;
    WHILE @@FETCH_STATUS=0
    BEGIN
        IF @RecepcionEstado NOT IN('BORRADOR','VALIDADA','CONTABILIZADA') THROW 51853,'Una recepción objetivo no admite costos adicionales en su estado actual.',1;
        UPDATE inv.RecepcionMercanciaLinea SET CostoAdicionalAsignado=CostoAdicionalAsignado+@Valor,CostoTotalCapitalizable=CostoTotalCapitalizable+@Valor
        WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaLineaId=@RecepcionLineaId;
        IF @RecepcionEstado='CONTABILIZADA' AND @Valor>0
        BEGIN
            IF @PeriodoInventarioId IS NULL OR @FechaContable IS NULL THROW 51854,'La aplicación tardía requiere periodo y fecha contable.',1;
            SELECT @MovimientoRecepcionId=MovimientoInventarioId FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='RECEPCION_MERCANCIA' AND DocumentoLineaOrigenId=@RecepcionLineaId;
            IF @MovimientoRecepcionId IS NULL THROW 51855,'No se encontró el movimiento original de la recepción.',1;
            IF EXISTS
            (
                SELECT 1 FROM inv.MovimientoInventario m
                WHERE m.EmpresaId=@EmpresaId AND m.BodegaId=@BodegaId AND m.ArticuloId=@ArticuloId AND m.MovimientoInventarioId>@MovimientoRecepcionId
                  AND NOT(m.TipoDocumentoOrigen='RECEPCION_MERCANCIA' AND m.DocumentoOrigenId=@RecepcionId)
                  AND NOT(m.TipoDocumentoOrigen='DISTRIBUCION_COSTO' AND m.DocumentoOrigenId=@DistribucionCostoId)
            ) THROW 51856,'Existen movimientos posteriores; el costo tardío debe tratarse mediante la variación contable aprobada.',1;
            DELETE FROM @R;
            INSERT @R EXEC inv.usp_AjustarValorInventario @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoInventarioId,
                @FechaMovimiento=@FechaContable,@FechaContable=@FechaContable,@TipoDocumentoOrigen='DISTRIBUCION_COSTO',@DocumentoOrigenId=@DistribucionCostoId,
                @DocumentoLineaOrigenId=@DistribucionLineaId,@NumeroDocumento=@Numero,@ValorAjuste=@Valor,@IdempotencyKey=@Key,@UsuarioId=@UsuarioId,
                @CorrelationId=@CorrelationId,@MovimientoRelacionadoId=@MovimientoRecepcionId;
        END;
        SET @MovimientoRecepcionId=NULL;
        FETCH NEXT FROM c INTO @DistribucionLineaId,@RecepcionLineaId,@Valor,@Key,@RecepcionId,@RecepcionEstado,@BodegaId,@ArticuloId;
    END;
    CLOSE c; DEALLOCATE c;
    UPDATE cost.DistribucionCosto SET Estado='APLICADA',AplicadaEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@EmpresaId AND DistribucionCostoId=@DistribucionCostoId;
    UPDATE cost.DocumentoCostoAdquisicion SET Estado='APLICADO' WHERE EmpresaId=@EmpresaId AND DocumentoCostoId=@DocumentoCostoId;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresPosteriores,AplicacionOrigen,CorrelationId)
    VALUES(@EmpresaId,@UsuarioId,'COSTO_DISTRIBUCION_APLICADA','cost.DistribucionCosto',CONVERT(nvarchar(100),@DistribucionCostoId),@Numero,N'{"estado":"APLICADA"}','COSTOS',@CorrelationId);
    COMMIT;
    SELECT @DistribucionCostoId DistribucionCostoId,CAST('APLICADA' AS varchar(20)) Estado,(SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='DISTRIBUCION_COSTO' AND DocumentoOrigenId=@DistribucionCostoId) AjustesKardex,CAST(0 AS bit) YaExistia;
END;
GO
