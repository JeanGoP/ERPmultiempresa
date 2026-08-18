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

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='012_physical_count_application')
BEGIN
    BEGIN TRANSACTION;
    ALTER TABLE inv.ConteoFisico ADD PeriodoInventarioId bigint NULL,FechaContableAplicacion date NULL,AplicadoEnUtc datetime2(7) NULL;
    ALTER TABLE inv.ConteoFisico ADD CONSTRAINT FK_ConteoFisico_Periodo FOREIGN KEY(EmpresaId,PeriodoInventarioId) REFERENCES core.PeriodoInventario(EmpresaId,PeriodoInventarioId);
    ALTER TABLE inv.ConteoFisicoLinea ADD EntradaIdempotencyKey uniqueidentifier NOT NULL CONSTRAINT DF_ConteoLinea_EntradaKey DEFAULT NEWID(),
        SalidaIdempotencyKey uniqueidentifier NOT NULL CONSTRAINT DF_ConteoLinea_SalidaKey DEFAULT NEWID(),
        CostoUnitarioAjuste decimal(20,8) NULL;
    EXEC(N'ALTER TABLE inv.ConteoFisicoLinea ADD CONSTRAINT CK_ConteoLinea_CostoAjuste CHECK(CostoUnitarioAjuste IS NULL OR CostoUnitarioAjuste>=0);');
    EXEC(N'CREATE UNIQUE INDEX UX_ConteoLinea_EntradaKey ON inv.ConteoFisicoLinea(EmpresaId,EntradaIdempotencyKey);');
    EXEC(N'CREATE UNIQUE INDEX UX_ConteoLinea_SalidaKey ON inv.ConteoFisicoLinea(EmpresaId,SalidaIdempotencyKey);');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('012_physical_count_application',N'Aplicación segura e idempotente de diferencias de conteo físico');
    COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_AplicarConteoFisico
    @EmpresaId bigint,@ConteoFisicoId bigint,@PeriodoInventarioId bigint,@FechaContable date,
    @UsuarioId bigint=NULL,@CorrelationId uniqueidentifier=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @CorrelationId IS NULL SET @CorrelationId=NEWID();
    BEGIN TRANSACTION;
    DECLARE @Numero nvarchar(50),@BodegaId bigint,@FechaCorte datetime2(7),@Estado varchar(20);
    SELECT @Numero=Numero,@BodegaId=BodegaId,@FechaCorte=FechaCorte,@Estado=Estado
    FROM inv.ConteoFisico WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoFisicoId;
    IF @Estado IS NULL THROW 51820,'El conteo no existe o no pertenece a la empresa.',1;
    IF @Estado='APLICADO'
    BEGIN
        COMMIT;
        SELECT @ConteoFisicoId ConteoFisicoId,@Estado Estado,(SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='CONTEO_FISICO' AND DocumentoOrigenId=@ConteoFisicoId) Movimientos,CAST(1 AS bit) YaExistia;
        RETURN;
    END;
    IF @Estado<>'APROBADO' THROW 51821,'Solo un conteo aprobado puede aplicarse.',1;
    IF NOT EXISTS(SELECT 1 FROM inv.ConteoFisicoLinea WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoFisicoId) THROW 51822,'El conteo no contiene líneas.',1;
    IF EXISTS(SELECT 1 FROM inv.ConteoFisicoLinea WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoFisicoId AND CantidadAprobada IS NULL)
        THROW 51823,'Todas las líneas requieren cantidad aprobada.',1;
    IF EXISTS(SELECT 1 FROM inv.ConteoFisicoLinea WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoFisicoId AND LoteId IS NOT NULL AND UbicacionId IS NULL)
        THROW 51827,'Una línea por lote requiere ubicación.',1;
    IF EXISTS
    (
        SELECT ArticuloId,COALESCE(UbicacionId,0),COALESCE(LoteId,0)
        FROM inv.ConteoFisicoLinea WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoFisicoId
        GROUP BY ArticuloId,COALESCE(UbicacionId,0),COALESCE(LoteId,0) HAVING COUNT(*)>1
    ) THROW 51824,'El conteo contiene dimensiones de artículo, ubicación y lote duplicadas.',1;

    DECLARE @LineaId bigint,@ArticuloId bigint,@UbicacionId bigint,@LoteId bigint,@Teorica decimal(20,6),@Aprobada decimal(20,6),@Actual decimal(20,6),
            @Diferencia decimal(20,6),@CostoAjuste decimal(20,8),@CostoActual decimal(20,8),@EntradaKey uniqueidentifier,@SalidaKey uniqueidentifier;
    DECLARE @CantidadSalida decimal(20,6);
    DECLARE @R TABLE(MovimientoInventarioId bigint,ExistenciaPosterior decimal(20,6),CostoPromedioPosterior decimal(20,8),ValorTotalPosterior decimal(20,4),YaExistia bit);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT ConteoFisicoLineaId,ArticuloId,UbicacionId,LoteId,ExistenciaTeorica,CantidadAprobada,CostoUnitarioAjuste,EntradaIdempotencyKey,SalidaIdempotencyKey
        FROM inv.ConteoFisicoLinea WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoFisicoId ORDER BY ArticuloId,ConteoFisicoLineaId;
    OPEN c; FETCH NEXT FROM c INTO @LineaId,@ArticuloId,@UbicacionId,@LoteId,@Teorica,@Aprobada,@CostoAjuste,@EntradaKey,@SalidaKey;
    WHILE @@FETCH_STATUS=0
    BEGIN
        IF @LoteId IS NOT NULL
            SELECT @Actual=Existencia FROM inv.SaldoArticuloLoteUbicacion WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND UbicacionId=@UbicacionId AND ArticuloId=@ArticuloId AND LoteId=@LoteId;
        ELSE IF @UbicacionId IS NOT NULL
            SELECT @Actual=Existencia FROM inv.SaldoArticuloUbicacion WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND UbicacionId=@UbicacionId AND ArticuloId=@ArticuloId;
        ELSE
            SELECT @Actual=Existencia FROM inv.SaldoArticuloBodega WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId;
        SET @Actual=COALESCE(@Actual,0);
        IF @Actual<>@Teorica THROW 51825,'El saldo cambió después del corte; recalcule o reconcilie el conteo antes de aplicarlo.',1;
        SET @Diferencia=@Aprobada-@Teorica;
        UPDATE inv.ConteoFisicoLinea SET DiferenciaAprobada=@Diferencia WHERE EmpresaId=@EmpresaId AND ConteoFisicoLineaId=@LineaId;
        IF @Diferencia>0
        BEGIN
            SELECT @CostoActual=CostoPromedio FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId;
            SET @CostoActual=COALESCE(NULLIF(@CostoActual,0),@CostoAjuste);
            IF @CostoActual IS NULL THROW 51826,'Un ajuste positivo sin costo promedio requiere costo unitario aprobado.',1;
            DELETE FROM @R;
            INSERT @R EXEC inv.usp_ContabilizarEntrada @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@UbicacionId=@UbicacionId,@ArticuloId=@ArticuloId,@LoteId=@LoteId,
                @PeriodoInventarioId=@PeriodoInventarioId,@FechaMovimiento=@FechaCorte,@FechaContable=@FechaContable,@TipoMovimiento='AJUSTE_CONTEO_ENTRADA',
                @ModuloOrigen='INVENTARIO',@TipoDocumentoOrigen='CONTEO_FISICO',@DocumentoOrigenId=@ConteoFisicoId,@DocumentoLineaOrigenId=@LineaId,
                @NumeroDocumento=@Numero,@CantidadEntrada=@Diferencia,@CostoUnitarioEntrada=@CostoActual,@IdempotencyKey=@EntradaKey,@UsuarioId=@UsuarioId,@CorrelationId=@CorrelationId;
        END
        ELSE IF @Diferencia<0
        BEGIN
            SET @CantidadSalida=-@Diferencia;
            DELETE FROM @R;
            INSERT @R EXEC inv.usp_ContabilizarSalida @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@UbicacionId=@UbicacionId,@ArticuloId=@ArticuloId,@LoteId=@LoteId,
                @PeriodoInventarioId=@PeriodoInventarioId,@FechaMovimiento=@FechaCorte,@FechaContable=@FechaContable,@TipoMovimiento='AJUSTE_CONTEO_SALIDA',
                @ModuloOrigen='INVENTARIO',@TipoDocumentoOrigen='CONTEO_FISICO',@DocumentoOrigenId=@ConteoFisicoId,@DocumentoLineaOrigenId=@LineaId,
                @NumeroDocumento=@Numero,@CantidadSalida=@CantidadSalida,@IdempotencyKey=@SalidaKey,@UsuarioId=@UsuarioId,@CorrelationId=@CorrelationId;
        END;
        SET @Actual=NULL; SET @CostoActual=NULL;
        FETCH NEXT FROM c INTO @LineaId,@ArticuloId,@UbicacionId,@LoteId,@Teorica,@Aprobada,@CostoAjuste,@EntradaKey,@SalidaKey;
    END;
    CLOSE c; DEALLOCATE c;
    UPDATE inv.ConteoFisico SET Estado='APLICADO',PeriodoInventarioId=@PeriodoInventarioId,FechaContableAplicacion=@FechaContable,AplicadoEnUtc=SYSUTCDATETIME()
    WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoFisicoId;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresPosteriores,AplicacionOrigen,CorrelationId)
    VALUES(@EmpresaId,@UsuarioId,'CONTEO_FISICO_APLICADO','inv.ConteoFisico',CONVERT(nvarchar(100),@ConteoFisicoId),@Numero,N'{"estado":"APLICADO"}','INVENTARIO',@CorrelationId);
    COMMIT;
    SELECT @ConteoFisicoId ConteoFisicoId,CAST('APLICADO' AS varchar(20)) Estado,(SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='CONTEO_FISICO' AND DocumentoOrigenId=@ConteoFisicoId) Movimientos,CAST(0 AS bit) YaExistia;
END;
GO
