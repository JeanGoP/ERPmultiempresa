SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='022_sales_returns')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
    CREATE TABLE inv.DevolucionVenta
    (
        DevolucionVentaId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        DevolucionGuid uniqueidentifier NOT NULL CONSTRAINT DF_DevolucionVenta_Guid DEFAULT NEWSEQUENTIALID(),
        Numero nvarchar(50) NOT NULL,
        TerceroId bigint NULL,
        BodegaId bigint NOT NULL,
        PeriodoInventarioId bigint NOT NULL,
        FechaMovimiento datetime2(7) NOT NULL,
        FechaContable date NOT NULL,
        Motivo nvarchar(500) NOT NULL,
        Estado varchar(15) NOT NULL CONSTRAINT DF_DevolucionVenta_Estado DEFAULT 'BORRADOR',
        CreadoPorUsuarioId bigint NULL,
        ContabilizadoEnUtc datetime2(7) NULL,
        CONSTRAINT PK_DevolucionVenta PRIMARY KEY CLUSTERED(DevolucionVentaId),
        CONSTRAINT UQ_DevolucionVenta_EmpresaId UNIQUE(EmpresaId,DevolucionVentaId),
        CONSTRAINT UQ_DevolucionVenta_Guid UNIQUE(DevolucionGuid),
        CONSTRAINT UQ_DevolucionVenta_Numero UNIQUE(EmpresaId,Numero),
        CONSTRAINT FK_DevolucionVenta_Tercero FOREIGN KEY(EmpresaId,TerceroId) REFERENCES ter.Tercero(EmpresaId,TerceroId),
        CONSTRAINT FK_DevolucionVenta_Bodega FOREIGN KEY(EmpresaId,BodegaId) REFERENCES inv.Bodega(EmpresaId,BodegaId),
        CONSTRAINT FK_DevolucionVenta_Periodo FOREIGN KEY(EmpresaId,PeriodoInventarioId) REFERENCES core.PeriodoInventario(EmpresaId,PeriodoInventarioId),
        CONSTRAINT FK_DevolucionVenta_Usuario FOREIGN KEY(CreadoPorUsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_DevolucionVenta_Estado CHECK(Estado IN('BORRADOR','VALIDADA','CONTABILIZADA','REVERTIDA','CANCELADA'))
    );
    CREATE TABLE inv.DevolucionVentaLinea
    (
        DevolucionVentaLineaId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        DevolucionVentaId bigint NOT NULL,
        NumeroLinea int NOT NULL,
        MovimientoSalidaOriginalId bigint NOT NULL,
        ArticuloId bigint NOT NULL,
        CantidadBase decimal(20,6) NOT NULL,
        UbicacionId bigint NULL,
        LoteId bigint NULL,
        IdempotencyKey uniqueidentifier NOT NULL CONSTRAINT DF_DevolucionVentaLinea_Key DEFAULT NEWID(),
        CostoUnitarioEntrada decimal(20,8) NULL,
        CONSTRAINT PK_DevolucionVentaLinea PRIMARY KEY CLUSTERED(DevolucionVentaLineaId),
        CONSTRAINT UQ_DevolucionVentaLinea_Numero UNIQUE(EmpresaId,DevolucionVentaId,NumeroLinea),
        CONSTRAINT UQ_DevolucionVentaLinea_Key UNIQUE(EmpresaId,IdempotencyKey),
        CONSTRAINT FK_DevolucionVentaLinea_Devolucion FOREIGN KEY(EmpresaId,DevolucionVentaId) REFERENCES inv.DevolucionVenta(EmpresaId,DevolucionVentaId),
        CONSTRAINT FK_DevolucionVentaLinea_Movimiento FOREIGN KEY(EmpresaId,MovimientoSalidaOriginalId) REFERENCES inv.MovimientoInventario(EmpresaId,MovimientoInventarioId),
        CONSTRAINT FK_DevolucionVentaLinea_Articulo FOREIGN KEY(EmpresaId,ArticuloId) REFERENCES inv.Articulo(EmpresaId,ArticuloId),
        CONSTRAINT FK_DevolucionVentaLinea_Ubicacion FOREIGN KEY(EmpresaId,UbicacionId) REFERENCES inv.Ubicacion(EmpresaId,UbicacionId),
        CONSTRAINT FK_DevolucionVentaLinea_Lote FOREIGN KEY(EmpresaId,LoteId) REFERENCES inv.Lote(EmpresaId,LoteId),
        CONSTRAINT CK_DevolucionVentaLinea_Cantidad CHECK(CantidadBase>0)
    );
    CREATE INDEX IX_DevolucionVentaLinea_Original ON inv.DevolucionVentaLinea(EmpresaId,MovimientoSalidaOriginalId) INCLUDE(CantidadBase,DevolucionVentaId);
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.DevolucionVenta;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.DevolucionVenta AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.DevolucionVenta AFTER UPDATE;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.DevolucionVentaLinea;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.DevolucionVentaLinea AFTER INSERT;');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('022_sales_returns',N'Devoluciones de venta al costo y origen de la salida original');
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_ContabilizarDevolucionVenta
    @EmpresaId bigint,@DevolucionVentaId bigint,@UsuarioId bigint=NULL,@CorrelationId uniqueidentifier=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @CorrelationId IS NULL SET @CorrelationId=NEWID();
    BEGIN TRANSACTION;
    DECLARE @Numero nvarchar(50),@TerceroId bigint,@BodegaId bigint,@PeriodoId bigint,@FechaMovimiento datetime2(7),@FechaContable date,@Estado varchar(15);
    SELECT @Numero=Numero,@TerceroId=TerceroId,@BodegaId=BodegaId,@PeriodoId=PeriodoInventarioId,@FechaMovimiento=FechaMovimiento,@FechaContable=FechaContable,@Estado=Estado
    FROM inv.DevolucionVenta WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND DevolucionVentaId=@DevolucionVentaId;
    IF @Estado IS NULL THROW 51950,'La devolución de venta no existe o no pertenece a la empresa.',1;
    IF @Estado='CONTABILIZADA'
    BEGIN COMMIT; SELECT @DevolucionVentaId DevolucionVentaId,@Estado Estado,(SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='DEVOLUCION_VENTA' AND DocumentoOrigenId=@DevolucionVentaId) Movimientos,CAST(1 AS bit) YaExistia; RETURN; END;
    IF @Estado NOT IN('BORRADOR','VALIDADA') THROW 51951,'La devolución de venta no puede contabilizarse en su estado actual.',1;
    IF NOT EXISTS(SELECT 1 FROM inv.DevolucionVentaLinea WHERE EmpresaId=@EmpresaId AND DevolucionVentaId=@DevolucionVentaId) THROW 51952,'La devolución de venta no contiene líneas.',1;

    DECLARE @LineaId bigint,@MovimientoOriginalId bigint,@ArticuloId bigint,@UbicacionId bigint,@LoteId bigint,@Cantidad decimal(20,6),@Key uniqueidentifier,@Costo decimal(20,8),@CantidadOriginal decimal(20,6),@LockResult int,@LockResource nvarchar(255);
    DECLARE @R TABLE(MovimientoInventarioId bigint,ExistenciaPosterior decimal(20,6),CostoPromedioPosterior decimal(20,8),ValorTotalPosterior decimal(20,4),YaExistia bit);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT DevolucionVentaLineaId,MovimientoSalidaOriginalId,ArticuloId,UbicacionId,LoteId,CantidadBase,IdempotencyKey
        FROM inv.DevolucionVentaLinea WHERE EmpresaId=@EmpresaId AND DevolucionVentaId=@DevolucionVentaId ORDER BY MovimientoSalidaOriginalId,DevolucionVentaLineaId;
    OPEN c; FETCH NEXT FROM c INTO @LineaId,@MovimientoOriginalId,@ArticuloId,@UbicacionId,@LoteId,@Cantidad,@Key;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @LockResource=CONCAT(N'DEVVENTA:',@EmpresaId,N':',@MovimientoOriginalId);
        EXEC @LockResult=sys.sp_getapplock @Resource=@LockResource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=15000;
        IF @LockResult<0 THROW 51953,'No fue posible bloquear la cantidad retornable de la venta.',1;
        SELECT @CantidadOriginal=CantidadSalida,@Costo=CostoUnitarioMovimiento FROM inv.MovimientoInventario
        WHERE EmpresaId=@EmpresaId AND MovimientoInventarioId=@MovimientoOriginalId AND ArticuloId=@ArticuloId AND CantidadSalida>0;
        IF @CantidadOriginal IS NULL THROW 51954,'La línea no corresponde a una salida original del artículo.',1;
        IF @Cantidad+COALESCE((SELECT SUM(dl.CantidadBase) FROM inv.DevolucionVentaLinea dl JOIN inv.DevolucionVenta dh ON dh.EmpresaId=dl.EmpresaId AND dh.DevolucionVentaId=dl.DevolucionVentaId WHERE dl.EmpresaId=@EmpresaId AND dl.MovimientoSalidaOriginalId=@MovimientoOriginalId AND dh.Estado='CONTABILIZADA' AND dh.DevolucionVentaId<>@DevolucionVentaId),0)>@CantidadOriginal
            THROW 51955,'La cantidad devuelta acumulada supera la salida original.',1;
        DELETE FROM @R;
        INSERT @R EXEC inv.usp_ContabilizarEntrada @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@UbicacionId=@UbicacionId,@ArticuloId=@ArticuloId,@LoteId=@LoteId,
            @PeriodoInventarioId=@PeriodoId,@FechaMovimiento=@FechaMovimiento,@FechaContable=@FechaContable,@TipoMovimiento='DEVOLUCION_VENTA',@ModuloOrigen='VENTAS',
            @TipoDocumentoOrigen='DEVOLUCION_VENTA',@DocumentoOrigenId=@DevolucionVentaId,@DocumentoLineaOrigenId=@LineaId,@NumeroDocumento=@Numero,@TerceroId=@TerceroId,
            @CantidadEntrada=@Cantidad,@CostoUnitarioEntrada=@Costo,@IdempotencyKey=@Key,@UsuarioId=@UsuarioId,@CorrelationId=@CorrelationId,@MovimientoRelacionadoId=@MovimientoOriginalId;
        UPDATE inv.DevolucionVentaLinea SET CostoUnitarioEntrada=@Costo WHERE EmpresaId=@EmpresaId AND DevolucionVentaLineaId=@LineaId;
        FETCH NEXT FROM c INTO @LineaId,@MovimientoOriginalId,@ArticuloId,@UbicacionId,@LoteId,@Cantidad,@Key;
    END;
    CLOSE c; DEALLOCATE c;
    UPDATE inv.DevolucionVenta SET Estado='CONTABILIZADA',ContabilizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@EmpresaId AND DevolucionVentaId=@DevolucionVentaId;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresPosteriores,AplicacionOrigen,CorrelationId)
    VALUES(@EmpresaId,@UsuarioId,'DEVOLUCION_VENTA_CONTABILIZADA','inv.DevolucionVenta',CONVERT(nvarchar(100),@DevolucionVentaId),@Numero,N'{"estado":"CONTABILIZADA"}','VENTAS',@CorrelationId);
    COMMIT;
    SELECT @DevolucionVentaId DevolucionVentaId,CAST('CONTABILIZADA' AS varchar(15)) Estado,(SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='DEVOLUCION_VENTA' AND DocumentoOrigenId=@DevolucionVentaId) Movimientos,CAST(0 AS bit) YaExistia;
END;
GO
