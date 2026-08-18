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

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='011_supplier_returns')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
    CREATE TABLE inv.DevolucionProveedor
    (
        DevolucionProveedorId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        DevolucionGuid uniqueidentifier NOT NULL CONSTRAINT DF_DevolucionProveedor_Guid DEFAULT NEWSEQUENTIALID(),
        Numero nvarchar(50) NOT NULL,
        TerceroId bigint NOT NULL,
        BodegaId bigint NOT NULL,
        PeriodoInventarioId bigint NOT NULL,
        FechaMovimiento datetime2(7) NOT NULL,
        FechaContable date NOT NULL,
        Motivo nvarchar(500) NOT NULL,
        Estado varchar(15) NOT NULL CONSTRAINT DF_DevolucionProveedor_Estado DEFAULT 'BORRADOR',
        CreadoPorUsuarioId bigint NULL,
        ContabilizadoEnUtc datetime2(7) NULL,
        RowVersion rowversion NOT NULL,
        CONSTRAINT PK_DevolucionProveedor PRIMARY KEY CLUSTERED(DevolucionProveedorId),
        CONSTRAINT UQ_DevolucionProveedor_EmpresaId UNIQUE(EmpresaId,DevolucionProveedorId),
        CONSTRAINT UQ_DevolucionProveedor_Guid UNIQUE(DevolucionGuid),
        CONSTRAINT UQ_DevolucionProveedor_Numero UNIQUE(EmpresaId,Numero),
        CONSTRAINT FK_DevolucionProveedor_Tercero FOREIGN KEY(EmpresaId,TerceroId) REFERENCES ter.Tercero(EmpresaId,TerceroId),
        CONSTRAINT FK_DevolucionProveedor_Bodega FOREIGN KEY(EmpresaId,BodegaId) REFERENCES inv.Bodega(EmpresaId,BodegaId),
        CONSTRAINT FK_DevolucionProveedor_Periodo FOREIGN KEY(EmpresaId,PeriodoInventarioId) REFERENCES core.PeriodoInventario(EmpresaId,PeriodoInventarioId),
        CONSTRAINT FK_DevolucionProveedor_Usuario FOREIGN KEY(CreadoPorUsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_DevolucionProveedor_Estado CHECK(Estado IN('BORRADOR','VALIDADA','CONTABILIZADA','REVERTIDA','CANCELADA'))
    );
    CREATE TABLE inv.DevolucionProveedorLinea
    (
        DevolucionProveedorLineaId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        DevolucionProveedorId bigint NOT NULL,
        NumeroLinea int NOT NULL,
        RecepcionMercanciaLineaId bigint NOT NULL,
        ArticuloId bigint NOT NULL,
        CantidadBase decimal(20,6) NOT NULL,
        UbicacionId bigint NULL,
        LoteId bigint NULL,
        IdempotencyKey uniqueidentifier NOT NULL CONSTRAINT DF_DevolucionProveedorLinea_Key DEFAULT NEWID(),
        CostoUnitarioSalida decimal(20,8) NULL,
        CONSTRAINT PK_DevolucionProveedorLinea PRIMARY KEY CLUSTERED(DevolucionProveedorLineaId),
        CONSTRAINT UQ_DevolucionProveedorLinea_EmpresaId UNIQUE(EmpresaId,DevolucionProveedorLineaId),
        CONSTRAINT UQ_DevolucionProveedorLinea_Numero UNIQUE(EmpresaId,DevolucionProveedorId,NumeroLinea),
        CONSTRAINT UQ_DevolucionProveedorLinea_Key UNIQUE(EmpresaId,IdempotencyKey),
        CONSTRAINT FK_DevolucionProveedorLinea_Devolucion FOREIGN KEY(EmpresaId,DevolucionProveedorId) REFERENCES inv.DevolucionProveedor(EmpresaId,DevolucionProveedorId),
        CONSTRAINT FK_DevolucionProveedorLinea_Recepcion FOREIGN KEY(EmpresaId,RecepcionMercanciaLineaId) REFERENCES inv.RecepcionMercanciaLinea(EmpresaId,RecepcionMercanciaLineaId),
        CONSTRAINT FK_DevolucionProveedorLinea_Articulo FOREIGN KEY(EmpresaId,ArticuloId) REFERENCES inv.Articulo(EmpresaId,ArticuloId),
        CONSTRAINT FK_DevolucionProveedorLinea_Ubicacion FOREIGN KEY(EmpresaId,UbicacionId) REFERENCES inv.Ubicacion(EmpresaId,UbicacionId),
        CONSTRAINT FK_DevolucionProveedorLinea_Lote FOREIGN KEY(EmpresaId,LoteId) REFERENCES inv.Lote(EmpresaId,LoteId),
        CONSTRAINT CK_DevolucionProveedorLinea_Cantidad CHECK(CantidadBase>0)
    );
    CREATE INDEX IX_DevolucionProveedorLinea_Recepcion ON inv.DevolucionProveedorLinea(EmpresaId,RecepcionMercanciaLineaId) INCLUDE(CantidadBase,DevolucionProveedorId);
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.DevolucionProveedor;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.DevolucionProveedor AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.DevolucionProveedor AFTER UPDATE;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.DevolucionProveedorLinea;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.DevolucionProveedorLinea AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.DevolucionProveedorLinea AFTER UPDATE;');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('011_supplier_returns',N'Devoluciones a proveedor vinculadas a la recepción original');
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_ContabilizarDevolucionProveedor
    @EmpresaId bigint,@DevolucionProveedorId bigint,@UsuarioId bigint=NULL,@CorrelationId uniqueidentifier=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @CorrelationId IS NULL SET @CorrelationId=NEWID();
    BEGIN TRANSACTION;
    DECLARE @Numero nvarchar(50),@TerceroId bigint,@BodegaId bigint,@PeriodoId bigint,@FechaMovimiento datetime2(7),@FechaContable date,@Estado varchar(15);
    SELECT @Numero=Numero,@TerceroId=TerceroId,@BodegaId=BodegaId,@PeriodoId=PeriodoInventarioId,@FechaMovimiento=FechaMovimiento,@FechaContable=FechaContable,@Estado=Estado
    FROM inv.DevolucionProveedor WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND DevolucionProveedorId=@DevolucionProveedorId;
    IF @Estado IS NULL THROW 51800,'La devolución no existe o no pertenece a la empresa.',1;
    IF @Estado='CONTABILIZADA'
    BEGIN
        COMMIT;
        SELECT @DevolucionProveedorId DevolucionProveedorId,@Estado Estado,(SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='DEVOLUCION_PROVEEDOR' AND DocumentoOrigenId=@DevolucionProveedorId) Movimientos,CAST(1 AS bit) YaExistia;
        RETURN;
    END;
    IF @Estado NOT IN('BORRADOR','VALIDADA') THROW 51801,'La devolución no puede contabilizarse en su estado actual.',1;
    IF NOT EXISTS(SELECT 1 FROM inv.DevolucionProveedorLinea WHERE EmpresaId=@EmpresaId AND DevolucionProveedorId=@DevolucionProveedorId) THROW 51802,'La devolución no contiene líneas.',1;
    IF EXISTS
    (
        SELECT 1 FROM inv.DevolucionProveedorLinea d
        JOIN inv.RecepcionMercanciaLinea r ON r.EmpresaId=d.EmpresaId AND r.RecepcionMercanciaLineaId=d.RecepcionMercanciaLineaId
        JOIN inv.RecepcionMercancia h ON h.EmpresaId=r.EmpresaId AND h.RecepcionMercanciaId=r.RecepcionMercanciaId
        WHERE d.EmpresaId=@EmpresaId AND d.DevolucionProveedorId=@DevolucionProveedorId
          AND (d.ArticuloId<>r.ArticuloId OR h.TerceroId<>@TerceroId OR h.Estado<>'CONTABILIZADA')
    ) THROW 51803,'Una línea no corresponde al artículo, proveedor o recepción contabilizada.',1;

    DECLARE @LineaId bigint,@RecepcionLineaId bigint,@ArticuloId bigint,@UbicacionId bigint,@LoteId bigint,@Cantidad decimal(20,6),@Key uniqueidentifier,@Costo decimal(20,8),@CostoOrigen decimal(20,8),@MovimientoId bigint,@LockResult int,@LockResource nvarchar(255);
    DECLARE @R TABLE(MovimientoInventarioId bigint,ExistenciaPosterior decimal(20,6),CostoPromedioPosterior decimal(20,8),ValorTotalPosterior decimal(20,4),YaExistia bit);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT DevolucionProveedorLineaId,RecepcionMercanciaLineaId,ArticuloId,UbicacionId,LoteId,CantidadBase,IdempotencyKey
        FROM inv.DevolucionProveedorLinea WHERE EmpresaId=@EmpresaId AND DevolucionProveedorId=@DevolucionProveedorId ORDER BY RecepcionMercanciaLineaId,DevolucionProveedorLineaId;
    OPEN c; FETCH NEXT FROM c INTO @LineaId,@RecepcionLineaId,@ArticuloId,@UbicacionId,@LoteId,@Cantidad,@Key;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @LockResource=CONCAT(N'DEVREC:',@EmpresaId,N':',@RecepcionLineaId);
        EXEC @LockResult=sys.sp_getapplock @Resource=@LockResource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=15000;
        IF @LockResult<0 THROW 51804,'No fue posible bloquear la cantidad retornable.',1;
        IF @Cantidad+COALESCE((SELECT SUM(dl.CantidadBase) FROM inv.DevolucionProveedorLinea dl JOIN inv.DevolucionProveedor dh ON dh.EmpresaId=dl.EmpresaId AND dh.DevolucionProveedorId=dl.DevolucionProveedorId
            WHERE dl.EmpresaId=@EmpresaId AND dl.RecepcionMercanciaLineaId=@RecepcionLineaId AND dh.Estado='CONTABILIZADA' AND dh.DevolucionProveedorId<>@DevolucionProveedorId),0)
           >(SELECT CantidadBase FROM inv.RecepcionMercanciaLinea WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaLineaId=@RecepcionLineaId)
            THROW 51805,'La cantidad devuelta acumulada supera la cantidad recibida.',1;
        SELECT @CostoOrigen=CAST(CostoTotalCapitalizable/CantidadBase AS decimal(20,8)) FROM inv.RecepcionMercanciaLinea
        WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaLineaId=@RecepcionLineaId;
        DELETE FROM @R;
        INSERT @R EXEC inv.usp_ContabilizarSalida @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@UbicacionId=@UbicacionId,@ArticuloId=@ArticuloId,@LoteId=@LoteId,
            @PeriodoInventarioId=@PeriodoId,@FechaMovimiento=@FechaMovimiento,@FechaContable=@FechaContable,@TipoMovimiento='DEVOLUCION_PROVEEDOR',
            @ModuloOrigen='COMPRAS',@TipoDocumentoOrigen='DEVOLUCION_PROVEEDOR',@DocumentoOrigenId=@DevolucionProveedorId,@DocumentoLineaOrigenId=@LineaId,
            @NumeroDocumento=@Numero,@TerceroId=@TerceroId,@CantidadSalida=@Cantidad,@IdempotencyKey=@Key,@UsuarioId=@UsuarioId,@CorrelationId=@CorrelationId,@CostoUnitarioForzado=@CostoOrigen;
        SELECT @MovimientoId=MovimientoInventarioId FROM @R;
        SELECT @Costo=CostoUnitarioMovimiento FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND MovimientoInventarioId=@MovimientoId;
        UPDATE inv.DevolucionProveedorLinea SET CostoUnitarioSalida=@Costo WHERE EmpresaId=@EmpresaId AND DevolucionProveedorLineaId=@LineaId;
        FETCH NEXT FROM c INTO @LineaId,@RecepcionLineaId,@ArticuloId,@UbicacionId,@LoteId,@Cantidad,@Key;
    END;
    CLOSE c; DEALLOCATE c;
    UPDATE inv.DevolucionProveedor SET Estado='CONTABILIZADA',ContabilizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@EmpresaId AND DevolucionProveedorId=@DevolucionProveedorId;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresPosteriores,AplicacionOrigen,CorrelationId)
    VALUES(@EmpresaId,@UsuarioId,'DEVOLUCION_PROVEEDOR_CONTABILIZADA','inv.DevolucionProveedor',CONVERT(nvarchar(100),@DevolucionProveedorId),@Numero,N'{"estado":"CONTABILIZADA"}','COMPRAS',@CorrelationId);
    COMMIT;
    SELECT @DevolucionProveedorId DevolucionProveedorId,CAST('CONTABILIZADA' AS varchar(15)) Estado,(SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='DEVOLUCION_PROVEEDOR' AND DocumentoOrigenId=@DevolucionProveedorId) Movimientos,CAST(0 AS bit) YaExistia;
END;
GO
