SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='031_inventory_reversals')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
    CREATE TABLE inv.ReversionMovimientoInventario
    (
        ReversionMovimientoInventarioId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        MovimientoOriginalId bigint NOT NULL,
        MovimientoReversionId bigint NULL,
        PeriodoInventarioId bigint NOT NULL,
        FechaContable date NOT NULL,
        Motivo nvarchar(500) NOT NULL,
        IdempotencyKey uniqueidentifier NOT NULL,
        Estado varchar(15) NOT NULL CONSTRAINT DF_ReversionMovimiento_Estado DEFAULT 'PENDIENTE',
        AprobacionOperacionId bigint NULL,
        RevertidoPorUsuarioId bigint NULL,
        CreadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_ReversionMovimiento_Fecha DEFAULT SYSUTCDATETIME(),
        ContabilizadoEnUtc datetime2(7) NULL,
        CONSTRAINT PK_ReversionMovimientoInventario PRIMARY KEY CLUSTERED(ReversionMovimientoInventarioId),
        CONSTRAINT UQ_ReversionMovimientoInventario_EmpresaId UNIQUE(EmpresaId,ReversionMovimientoInventarioId),
        CONSTRAINT UQ_ReversionMovimientoInventario_Original UNIQUE(EmpresaId,MovimientoOriginalId),
        CONSTRAINT UQ_ReversionMovimientoInventario_Key UNIQUE(EmpresaId,IdempotencyKey),
        CONSTRAINT FK_ReversionMovimiento_Original FOREIGN KEY(EmpresaId,MovimientoOriginalId) REFERENCES inv.MovimientoInventario(EmpresaId,MovimientoInventarioId),
        CONSTRAINT FK_ReversionMovimiento_Reversion FOREIGN KEY(EmpresaId,MovimientoReversionId) REFERENCES inv.MovimientoInventario(EmpresaId,MovimientoInventarioId),
        CONSTRAINT FK_ReversionMovimiento_Periodo FOREIGN KEY(EmpresaId,PeriodoInventarioId) REFERENCES core.PeriodoInventario(EmpresaId,PeriodoInventarioId),
        CONSTRAINT FK_ReversionMovimiento_Aprobacion FOREIGN KEY(EmpresaId,AprobacionOperacionId) REFERENCES seg.AprobacionOperacion(EmpresaId,AprobacionOperacionId),
        CONSTRAINT FK_ReversionMovimiento_Usuario FOREIGN KEY(RevertidoPorUsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_ReversionMovimiento_Estado CHECK(Estado IN('PENDIENTE','CONTABILIZADA','FALLIDA')),
        CONSTRAINT CK_ReversionMovimiento_Motivo CHECK(LEN(LTRIM(RTRIM(Motivo)))>=10)
    );
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.ReversionMovimientoInventario;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.ReversionMovimientoInventario AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.ReversionMovimientoInventario AFTER UPDATE;');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('031_inventory_reversals',N'Reversas de Kardex mediante movimiento contrario trazable y no destructivo');
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO

CREATE OR ALTER TRIGGER inv.TR_MovimientoInventario_ReversionSerial ON inv.MovimientoInventario AFTER INSERT AS
BEGIN
    SET NOCOUNT ON;
    INSERT inv.MovimientoInventarioUnidad
    (EmpresaId,MovimientoInventarioId,UnidadSerializadaId,EstadoAnterior,EstadoPosterior,BodegaAnteriorId,BodegaPosteriorId,UbicacionAnteriorId,UbicacionPosteriorId)
    SELECT i.EmpresaId,i.MovimientoInventarioId,mu.UnidadSerializadaId,s.Estado,
        CASE WHEN i.CantidadEntrada>0 THEN COALESCE(mu.EstadoAnterior,'DISPONIBLE') ELSE 'BAJA' END,
        s.BodegaActualId,CASE WHEN i.CantidadEntrada>0 THEN mu.BodegaAnteriorId ELSE NULL END,
        s.UbicacionActualId,CASE WHEN i.CantidadEntrada>0 THEN mu.UbicacionAnteriorId ELSE NULL END
    FROM inserted i
    JOIN inv.ReversionMovimientoInventario r ON r.EmpresaId=i.EmpresaId AND r.ReversionMovimientoInventarioId=i.DocumentoOrigenId
    JOIN inv.MovimientoInventarioUnidad mu ON mu.EmpresaId=r.EmpresaId AND mu.MovimientoInventarioId=r.MovimientoOriginalId
    JOIN inv.UnidadSerializada s ON s.EmpresaId=mu.EmpresaId AND s.UnidadSerializadaId=mu.UnidadSerializadaId
    WHERE i.TipoDocumentoOrigen='REVERSA_MOVIMIENTO';

    IF EXISTS
    (
        SELECT 1 FROM inserted i
        JOIN inv.ReversionMovimientoInventario r ON r.EmpresaId=i.EmpresaId AND r.ReversionMovimientoInventarioId=i.DocumentoOrigenId
        JOIN inv.MovimientoInventario o ON o.EmpresaId=r.EmpresaId AND o.MovimientoInventarioId=r.MovimientoOriginalId
        JOIN inv.Articulo a ON a.EmpresaId=o.EmpresaId AND a.ArticuloId=o.ArticuloId AND a.ManejaSerial=1
        WHERE i.TipoDocumentoOrigen='REVERSA_MOVIMIENTO'
          AND (SELECT COUNT(*) FROM inv.MovimientoInventarioUnidad x WHERE x.EmpresaId=o.EmpresaId AND x.MovimientoInventarioId=o.MovimientoInventarioId)
              <>CONVERT(int,COALESCE(NULLIF(o.CantidadEntrada,0),o.CantidadSalida))
    ) THROW 51968,'El movimiento serial original no tiene una unidad por cada cantidad.',1;

    UPDATE s SET Estado=x.EstadoPosterior,BodegaActualId=x.BodegaPosteriorId,UbicacionActualId=x.UbicacionPosteriorId
    FROM inv.UnidadSerializada s
    JOIN inv.MovimientoInventarioUnidad x ON x.EmpresaId=s.EmpresaId AND x.UnidadSerializadaId=s.UnidadSerializadaId
    JOIN inserted i ON i.EmpresaId=x.EmpresaId AND i.MovimientoInventarioId=x.MovimientoInventarioId
    WHERE i.TipoDocumentoOrigen='REVERSA_MOVIMIENTO';
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_ReversarMovimientoInventario
    @EmpresaId bigint,@MovimientoOriginalId bigint,@PeriodoInventarioId bigint,@FechaContable date,
    @Motivo nvarchar(500),@IdempotencyKey uniqueidentifier,@UsuarioId bigint=NULL,
    @AprobacionOperacionId bigint=NULL,@CorrelationId uniqueidentifier=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF LEN(LTRIM(RTRIM(COALESCE(@Motivo,N''))))<10 THROW 51969,'La reversa requiere un motivo de al menos 10 caracteres.',1;
    IF @UsuarioId IS NOT NULL AND seg.fn_TienePermiso(@EmpresaId,@UsuarioId,'INVENTARIO.AJUSTE.REVERSAR')=0
        THROW 51970,'El usuario no tiene permiso para reversar movimientos.',1;
    IF @AprobacionOperacionId IS NOT NULL AND NOT EXISTS
    (
        SELECT 1 FROM seg.AprobacionOperacion WHERE EmpresaId=@EmpresaId AND AprobacionOperacionId=@AprobacionOperacionId
          AND Estado='APROBADA' AND PermisoRequerido='INVENTARIO.AJUSTE.REVERSAR'
    ) THROW 51971,'La aprobacion indicada no es valida para reversar inventario.',1;
    IF @CorrelationId IS NULL SET @CorrelationId=NEWID();

    BEGIN TRANSACTION;
    DECLARE @ReversionId bigint,@ReversionMovimientoId bigint,@ArticuloId bigint,@BodegaId bigint,@UbicacionId bigint,@LoteId bigint,
        @CantidadEntrada decimal(20,6),@CantidadSalida decimal(20,6),@Costo decimal(20,8),@Numero nvarchar(50),@TipoDocumento varchar(40),
        @TerceroId bigint,@OrigenId bigint,@DisponibleOrigen decimal(20,6),@KeyMovimiento uniqueidentifier=NEWID(),@FechaMovimiento datetime2(7)=SYSUTCDATETIME();
    SELECT @ReversionId=ReversionMovimientoInventarioId,@ReversionMovimientoId=MovimientoReversionId
    FROM inv.ReversionMovimientoInventario WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND IdempotencyKey=@IdempotencyKey;
    IF @ReversionId IS NOT NULL
    BEGIN
        COMMIT;
        SELECT @ReversionId ReversionMovimientoInventarioId,@ReversionMovimientoId MovimientoReversionId,CAST(1 AS bit) YaExistia;
        RETURN;
    END;
    SELECT @ArticuloId=ArticuloId,@BodegaId=BodegaId,@UbicacionId=UbicacionId,@LoteId=LoteId,@CantidadEntrada=CantidadEntrada,@CantidadSalida=CantidadSalida,
        @Costo=CostoUnitarioMovimiento,@Numero=NumeroDocumento,@TipoDocumento=TipoDocumentoOrigen,@TerceroId=TerceroId
    FROM inv.MovimientoInventario WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND MovimientoInventarioId=@MovimientoOriginalId;
    IF @ArticuloId IS NULL THROW 51972,'El movimiento original no existe o no pertenece a la empresa.',1;
    IF @TipoDocumento IN('TRASLADO','CONTEO_FISICO','DEVOLUCION_PROVEEDOR','DEVOLUCION_VENTA','REVERSA_MOVIMIENTO','REGULARIZACION_NEGATIVO')
        THROW 51973,'Este movimiento pertenece a un flujo compuesto y debe revertirse desde su documento de origen.',1;
    IF EXISTS(SELECT 1 FROM inv.ReversionMovimientoInventario WHERE EmpresaId=@EmpresaId AND MovimientoOriginalId=@MovimientoOriginalId)
        THROW 51974,'El movimiento original ya tiene una reversa.',1;
    IF EXISTS(SELECT 1 FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND MovimientoRelacionadoId=@MovimientoOriginalId)
        THROW 51975,'El movimiento tiene operaciones posteriores relacionadas y no puede revertirse completo.',1;

    INSERT inv.ReversionMovimientoInventario(EmpresaId,MovimientoOriginalId,PeriodoInventarioId,FechaContable,Motivo,IdempotencyKey,AprobacionOperacionId,RevertidoPorUsuarioId)
    VALUES(@EmpresaId,@MovimientoOriginalId,@PeriodoInventarioId,@FechaContable,@Motivo,@IdempotencyKey,@AprobacionOperacionId,@UsuarioId);
    SET @ReversionId=SCOPE_IDENTITY();

    DECLARE @R TABLE(MovimientoInventarioId bigint,ExistenciaPosterior decimal(20,6),CostoPromedioPosterior decimal(20,8),ValorTotalPosterior decimal(20,4),YaExistia bit);
    IF @CantidadEntrada>0
    BEGIN
        SELECT @OrigenId=o.OrigenInventarioId,@DisponibleOrigen=s.CantidadDisponible
        FROM inv.OrigenInventario o JOIN inv.SaldoOrigenBodega s ON s.EmpresaId=o.EmpresaId AND s.OrigenInventarioId=o.OrigenInventarioId AND s.BodegaId=@BodegaId AND s.ArticuloId=@ArticuloId
        WHERE o.EmpresaId=@EmpresaId AND o.MovimientoEntradaInicialId=@MovimientoOriginalId;
        IF @OrigenId IS NULL OR @DisponibleOrigen<@CantidadEntrada THROW 51976,'La existencia del origen ya fue consumida o trasladada y no permite reversa directa.',1;
        BEGIN TRY
            EXEC sys.sp_set_session_context @key=N'OmitirOrigenAutomatico',@value=1;
            INSERT @R EXEC inv.usp_ContabilizarSalida @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@UbicacionId=@UbicacionId,@ArticuloId=@ArticuloId,@LoteId=@LoteId,
                @PeriodoInventarioId=@PeriodoInventarioId,@FechaMovimiento=@FechaMovimiento,@FechaContable=@FechaContable,@TipoMovimiento='REVERSA_ENTRADA',
                @ModuloOrigen='INVENTARIO',@TipoDocumentoOrigen='REVERSA_MOVIMIENTO',@DocumentoOrigenId=@ReversionId,@NumeroDocumento=@Numero,
                @TerceroId=@TerceroId,@CantidadSalida=@CantidadEntrada,@IdempotencyKey=@KeyMovimiento,@UsuarioId=@UsuarioId,@CorrelationId=@CorrelationId,
                @MovimientoRelacionadoId=@MovimientoOriginalId,@CostoUnitarioForzado=@Costo;
            EXEC sys.sp_set_session_context @key=N'OmitirOrigenAutomatico',@value=NULL;
        END TRY
        BEGIN CATCH
            EXEC sys.sp_set_session_context @key=N'OmitirOrigenAutomatico',@value=NULL;
            THROW;
        END CATCH;
        SELECT @ReversionMovimientoId=MovimientoInventarioId FROM @R;
        UPDATE inv.SaldoOrigenBodega SET CantidadDisponible=CantidadDisponible-@CantidadEntrada,ActualizadoEnUtc=SYSUTCDATETIME()
        WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId AND OrigenInventarioId=@OrigenId;
        INSERT inv.MovimientoOrigenInventario(EmpresaId,MovimientoInventarioId,OrigenInventarioId,CantidadSalida)
        VALUES(@EmpresaId,@ReversionMovimientoId,@OrigenId,@CantidadEntrada);
    END
    ELSE
    BEGIN
        INSERT @R EXEC inv.usp_ContabilizarEntrada @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@UbicacionId=@UbicacionId,@ArticuloId=@ArticuloId,@LoteId=@LoteId,
            @PeriodoInventarioId=@PeriodoInventarioId,@FechaMovimiento=@FechaMovimiento,@FechaContable=@FechaContable,@TipoMovimiento='REVERSA_SALIDA',
            @ModuloOrigen='INVENTARIO',@TipoDocumentoOrigen='REVERSA_MOVIMIENTO',@DocumentoOrigenId=@ReversionId,@NumeroDocumento=@Numero,
            @TerceroId=@TerceroId,@CantidadEntrada=@CantidadSalida,@CostoUnitarioEntrada=@Costo,@IdempotencyKey=@KeyMovimiento,@UsuarioId=@UsuarioId,
            @CorrelationId=@CorrelationId,@MovimientoRelacionadoId=@MovimientoOriginalId;
        SELECT @ReversionMovimientoId=MovimientoInventarioId FROM @R;
    END;

    UPDATE inv.ReversionMovimientoInventario SET MovimientoReversionId=@ReversionMovimientoId,Estado='CONTABILIZADA',ContabilizadoEnUtc=SYSUTCDATETIME()
    WHERE EmpresaId=@EmpresaId AND ReversionMovimientoInventarioId=@ReversionId;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresAnteriores,ValoresPosteriores,AplicacionOrigen,CorrelationId)
    VALUES(@EmpresaId,@UsuarioId,'MOVIMIENTO_INVENTARIO_REVERTIDO','inv.ReversionMovimientoInventario',CONVERT(nvarchar(100),@ReversionId),@Numero,
        CONCAT(N'{"movimientoOriginalId":',@MovimientoOriginalId,N'}'),CONCAT(N'{"movimientoReversionId":',@ReversionMovimientoId,N'}'),'INVENTARIO',@CorrelationId);
    COMMIT;
    SELECT @ReversionId ReversionMovimientoInventarioId,@ReversionMovimientoId MovimientoReversionId,CAST(0 AS bit) YaExistia;
END;
GO
