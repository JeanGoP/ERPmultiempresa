SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='029_serialized_unit_lifecycle')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;

    ALTER TABLE inv.TrasladoLinea ADD CONSTRAINT UQ_TrasladoLinea_EmpresaId UNIQUE(EmpresaId,TrasladoLineaId);
    ALTER TABLE inv.DevolucionVentaLinea ADD CONSTRAINT UQ_DevolucionVentaLinea_EmpresaId UNIQUE(EmpresaId,DevolucionVentaLineaId);

    CREATE TABLE inv.MovimientoInventarioUnidad
    (
        MovimientoInventarioUnidadId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        MovimientoInventarioId bigint NOT NULL,
        UnidadSerializadaId bigint NOT NULL,
        EstadoAnterior varchar(20) NULL,
        EstadoPosterior varchar(20) NOT NULL,
        BodegaAnteriorId bigint NULL,
        BodegaPosteriorId bigint NULL,
        UbicacionAnteriorId bigint NULL,
        UbicacionPosteriorId bigint NULL,
        CreadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_MovimientoInventarioUnidad_Fecha DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_MovimientoInventarioUnidad PRIMARY KEY CLUSTERED(MovimientoInventarioUnidadId),
        CONSTRAINT UQ_MovimientoInventarioUnidad UNIQUE(EmpresaId,MovimientoInventarioId,UnidadSerializadaId),
        CONSTRAINT FK_MovimientoInventarioUnidad_Movimiento FOREIGN KEY(EmpresaId,MovimientoInventarioId) REFERENCES inv.MovimientoInventario(EmpresaId,MovimientoInventarioId),
        CONSTRAINT FK_MovimientoInventarioUnidad_Unidad FOREIGN KEY(EmpresaId,UnidadSerializadaId) REFERENCES inv.UnidadSerializada(EmpresaId,UnidadSerializadaId),
        CONSTRAINT FK_MovimientoInventarioUnidad_BodegaAnterior FOREIGN KEY(EmpresaId,BodegaAnteriorId) REFERENCES inv.Bodega(EmpresaId,BodegaId),
        CONSTRAINT FK_MovimientoInventarioUnidad_BodegaPosterior FOREIGN KEY(EmpresaId,BodegaPosteriorId) REFERENCES inv.Bodega(EmpresaId,BodegaId),
        CONSTRAINT FK_MovimientoInventarioUnidad_UbicacionAnterior FOREIGN KEY(EmpresaId,UbicacionAnteriorId) REFERENCES inv.Ubicacion(EmpresaId,UbicacionId),
        CONSTRAINT FK_MovimientoInventarioUnidad_UbicacionPosterior FOREIGN KEY(EmpresaId,UbicacionPosteriorId) REFERENCES inv.Ubicacion(EmpresaId,UbicacionId)
    );
    CREATE INDEX IX_MovimientoInventarioUnidad_Unidad ON inv.MovimientoInventarioUnidad(EmpresaId,UnidadSerializadaId,MovimientoInventarioUnidadId DESC);

    CREATE TABLE inv.TrasladoLineaUnidad
    (
        TrasladoLineaUnidadId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        TrasladoLineaId bigint NOT NULL,
        UnidadSerializadaId bigint NOT NULL,
        CONSTRAINT PK_TrasladoLineaUnidad PRIMARY KEY CLUSTERED(TrasladoLineaUnidadId),
        CONSTRAINT UQ_TrasladoLineaUnidad UNIQUE(EmpresaId,TrasladoLineaId,UnidadSerializadaId),
        CONSTRAINT FK_TrasladoLineaUnidad_Linea FOREIGN KEY(EmpresaId,TrasladoLineaId) REFERENCES inv.TrasladoLinea(EmpresaId,TrasladoLineaId),
        CONSTRAINT FK_TrasladoLineaUnidad_Unidad FOREIGN KEY(EmpresaId,UnidadSerializadaId) REFERENCES inv.UnidadSerializada(EmpresaId,UnidadSerializadaId)
    );

    CREATE TABLE inv.DevolucionProveedorLineaUnidad
    (
        DevolucionProveedorLineaUnidadId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        DevolucionProveedorLineaId bigint NOT NULL,
        UnidadSerializadaId bigint NOT NULL,
        CONSTRAINT PK_DevolucionProveedorLineaUnidad PRIMARY KEY CLUSTERED(DevolucionProveedorLineaUnidadId),
        CONSTRAINT UQ_DevolucionProveedorLineaUnidad UNIQUE(EmpresaId,DevolucionProveedorLineaId,UnidadSerializadaId),
        CONSTRAINT FK_DevolucionProveedorLineaUnidad_Linea FOREIGN KEY(EmpresaId,DevolucionProveedorLineaId) REFERENCES inv.DevolucionProveedorLinea(EmpresaId,DevolucionProveedorLineaId),
        CONSTRAINT FK_DevolucionProveedorLineaUnidad_Unidad FOREIGN KEY(EmpresaId,UnidadSerializadaId) REFERENCES inv.UnidadSerializada(EmpresaId,UnidadSerializadaId)
    );

    CREATE TABLE inv.DevolucionVentaLineaUnidad
    (
        DevolucionVentaLineaUnidadId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        DevolucionVentaLineaId bigint NOT NULL,
        UnidadSerializadaId bigint NOT NULL,
        CONSTRAINT PK_DevolucionVentaLineaUnidad PRIMARY KEY CLUSTERED(DevolucionVentaLineaUnidadId),
        CONSTRAINT UQ_DevolucionVentaLineaUnidad UNIQUE(EmpresaId,DevolucionVentaLineaId,UnidadSerializadaId),
        CONSTRAINT FK_DevolucionVentaLineaUnidad_Linea FOREIGN KEY(EmpresaId,DevolucionVentaLineaId) REFERENCES inv.DevolucionVentaLinea(EmpresaId,DevolucionVentaLineaId),
        CONSTRAINT FK_DevolucionVentaLineaUnidad_Unidad FOREIGN KEY(EmpresaId,UnidadSerializadaId) REFERENCES inv.UnidadSerializada(EmpresaId,UnidadSerializadaId)
    );

    CREATE TABLE inv.SolicitudSalidaSerializada
    (
        SolicitudSalidaSerializadaId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        IdempotencyKey uniqueidentifier NOT NULL,
        ArticuloId bigint NOT NULL,
        BodegaId bigint NOT NULL,
        Estado varchar(15) NOT NULL CONSTRAINT DF_SolicitudSalidaSerializada_Estado DEFAULT 'PENDIENTE',
        CreadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_SolicitudSalidaSerializada_Fecha DEFAULT SYSUTCDATETIME(),
        ConsumidoEnUtc datetime2(7) NULL,
        CONSTRAINT PK_SolicitudSalidaSerializada PRIMARY KEY CLUSTERED(SolicitudSalidaSerializadaId),
        CONSTRAINT UQ_SolicitudSalidaSerializada_Key UNIQUE(EmpresaId,IdempotencyKey),
        CONSTRAINT UQ_SolicitudSalidaSerializada_Id UNIQUE(EmpresaId,SolicitudSalidaSerializadaId),
        CONSTRAINT FK_SolicitudSalidaSerializada_Articulo FOREIGN KEY(EmpresaId,ArticuloId) REFERENCES inv.Articulo(EmpresaId,ArticuloId),
        CONSTRAINT FK_SolicitudSalidaSerializada_Bodega FOREIGN KEY(EmpresaId,BodegaId) REFERENCES inv.Bodega(EmpresaId,BodegaId),
        CONSTRAINT CK_SolicitudSalidaSerializada_Estado CHECK(Estado IN('PENDIENTE','CONSUMIDA','CANCELADA'))
    );

    CREATE TABLE inv.SolicitudSalidaSerializadaUnidad
    (
        SolicitudSalidaSerializadaUnidadId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        SolicitudSalidaSerializadaId bigint NOT NULL,
        UnidadSerializadaId bigint NOT NULL,
        CONSTRAINT PK_SolicitudSalidaSerializadaUnidad PRIMARY KEY CLUSTERED(SolicitudSalidaSerializadaUnidadId),
        CONSTRAINT UQ_SolicitudSalidaSerializadaUnidad UNIQUE(EmpresaId,SolicitudSalidaSerializadaId,UnidadSerializadaId),
        CONSTRAINT FK_SolicitudSalidaSerializadaUnidad_Solicitud FOREIGN KEY(EmpresaId,SolicitudSalidaSerializadaId) REFERENCES inv.SolicitudSalidaSerializada(EmpresaId,SolicitudSalidaSerializadaId),
        CONSTRAINT FK_SolicitudSalidaSerializadaUnidad_Unidad FOREIGN KEY(EmpresaId,UnidadSerializadaId) REFERENCES inv.UnidadSerializada(EmpresaId,UnidadSerializadaId)
    );

    DECLARE @Tabla sysname;
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT Tabla FROM (VALUES
            (N'inv.MovimientoInventarioUnidad'),(N'inv.TrasladoLineaUnidad'),
            (N'inv.DevolucionProveedorLineaUnidad'),(N'inv.DevolucionVentaLineaUnidad'),
            (N'inv.SolicitudSalidaSerializada'),(N'inv.SolicitudSalidaSerializadaUnidad')) t(Tabla);
    OPEN c; FETCH NEXT FROM c INTO @Tabla;
    WHILE @@FETCH_STATUS=0
    BEGIN
        EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON '+@Tabla+N';');
        EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON '+@Tabla+N' AFTER INSERT;');
        EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON '+@Tabla+N' AFTER UPDATE;');
        FETCH NEXT FROM c INTO @Tabla;
    END;
    CLOSE c; DEALLOCATE c;

    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('029_serialized_unit_lifecycle',N'Trazabilidad por unidad serializada en ventas, traslados y devoluciones');
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO

CREATE OR ALTER TRIGGER inv.TR_MovimientoInventarioUnidad_Inmutable ON inv.MovimientoInventarioUnidad
INSTEAD OF UPDATE,DELETE
AS
BEGIN
    THROW 51980,'La bitacora de movimientos por unidad serializada es inmutable.',1;
END;
GO

CREATE OR ALTER TRIGGER inv.TR_MovimientoInventario_Seriales ON inv.MovimientoInventario AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS(SELECT 1 FROM inserted i JOIN inv.Articulo a ON a.EmpresaId=i.EmpresaId AND a.ArticuloId=i.ArticuloId WHERE a.ManejaSerial=1) RETURN;

    IF EXISTS
    (
        SELECT 1 FROM inserted i JOIN inv.Articulo a ON a.EmpresaId=i.EmpresaId AND a.ArticuloId=i.ArticuloId AND a.ManejaSerial=1
        WHERE COALESCE(NULLIF(i.CantidadEntrada,0),i.CantidadSalida)<>FLOOR(COALESCE(NULLIF(i.CantidadEntrada,0),i.CantidadSalida))
    ) THROW 51981,'Los movimientos serializados solo admiten cantidades enteras.',1;

    DECLARE @Asignadas TABLE
    (
        EmpresaId bigint,MovimientoInventarioId bigint,UnidadSerializadaId bigint,
        EstadoAnterior varchar(20),EstadoPosterior varchar(20),
        BodegaAnteriorId bigint,BodegaPosteriorId bigint,UbicacionAnteriorId bigint,UbicacionPosteriorId bigint
    );

    -- Traslados: la misma unidad acompana salida, transito y entrada a destino.
    INSERT @Asignadas
    SELECT i.EmpresaId,i.MovimientoInventarioId,u.UnidadSerializadaId,s.Estado,
        CASE WHEN i.TipoMovimiento='TRASLADO_ENTRADA' THEN 'DISPONIBLE' ELSE 'EN_TRANSITO' END,
        s.BodegaActualId,
        CASE WHEN i.TipoMovimiento='TRASLADO_SALIDA' THEN t.BodegaTransitoId
             WHEN i.TipoMovimiento='TRASLADO_SALIDA_TRANSITO' THEN NULL ELSE i.BodegaId END,
        s.UbicacionActualId,NULL
    FROM inserted i
    JOIN inv.TrasladoLineaUnidad u ON u.EmpresaId=i.EmpresaId AND u.TrasladoLineaId=i.DocumentoLineaOrigenId
    JOIN inv.UnidadSerializada s ON s.EmpresaId=u.EmpresaId AND s.UnidadSerializadaId=u.UnidadSerializadaId
    JOIN inv.Traslado t ON t.EmpresaId=i.EmpresaId AND t.TrasladoId=i.DocumentoOrigenId
    WHERE i.TipoDocumentoOrigen='TRASLADO';

    -- Devolucion al proveedor: la unidad sale definitivamente del inventario.
    INSERT @Asignadas
    SELECT i.EmpresaId,i.MovimientoInventarioId,u.UnidadSerializadaId,s.Estado,'DEVUELTA',s.BodegaActualId,NULL,s.UbicacionActualId,NULL
    FROM inserted i
    JOIN inv.DevolucionProveedorLineaUnidad u ON u.EmpresaId=i.EmpresaId AND u.DevolucionProveedorLineaId=i.DocumentoLineaOrigenId
    JOIN inv.DevolucionProveedorLinea l ON l.EmpresaId=u.EmpresaId AND l.DevolucionProveedorLineaId=u.DevolucionProveedorLineaId
    JOIN inv.RecepcionMercanciaUnidad ru ON ru.EmpresaId=l.EmpresaId AND ru.RecepcionMercanciaLineaId=l.RecepcionMercanciaLineaId AND ru.UnidadSerializadaId=u.UnidadSerializadaId
    JOIN inv.UnidadSerializada s ON s.EmpresaId=u.EmpresaId AND s.UnidadSerializadaId=u.UnidadSerializadaId
    WHERE i.TipoDocumentoOrigen='DEVOLUCION_PROVEEDOR';

    -- Devolucion de venta: solo pueden regresar unidades de la salida original.
    INSERT @Asignadas
    SELECT i.EmpresaId,i.MovimientoInventarioId,u.UnidadSerializadaId,s.Estado,'DISPONIBLE',s.BodegaActualId,i.BodegaId,s.UbicacionActualId,i.UbicacionId
    FROM inserted i
    JOIN inv.DevolucionVentaLineaUnidad u ON u.EmpresaId=i.EmpresaId AND u.DevolucionVentaLineaId=i.DocumentoLineaOrigenId
    JOIN inv.DevolucionVentaLinea l ON l.EmpresaId=u.EmpresaId AND l.DevolucionVentaLineaId=u.DevolucionVentaLineaId
    JOIN inv.MovimientoInventarioUnidad om ON om.EmpresaId=l.EmpresaId AND om.MovimientoInventarioId=l.MovimientoSalidaOriginalId AND om.UnidadSerializadaId=u.UnidadSerializadaId
    JOIN inv.UnidadSerializada s ON s.EmpresaId=u.EmpresaId AND s.UnidadSerializadaId=u.UnidadSerializadaId
    WHERE i.TipoDocumentoOrigen='DEVOLUCION_VENTA';

    -- Salidas ordinarias (venta, consumo o baja) preparadas por el procedimiento serializado.
    INSERT @Asignadas
    SELECT i.EmpresaId,i.MovimientoInventarioId,u.UnidadSerializadaId,s.Estado,
        CASE WHEN i.TipoMovimiento='VENTA' THEN 'VENDIDA' ELSE 'BAJA' END,
        s.BodegaActualId,NULL,s.UbicacionActualId,NULL
    FROM inserted i
    JOIN inv.SolicitudSalidaSerializada q ON q.EmpresaId=i.EmpresaId AND q.IdempotencyKey=i.IdempotencyKey AND q.Estado='PENDIENTE'
    JOIN inv.SolicitudSalidaSerializadaUnidad u ON u.EmpresaId=q.EmpresaId AND u.SolicitudSalidaSerializadaId=q.SolicitudSalidaSerializadaId
    JOIN inv.UnidadSerializada s ON s.EmpresaId=u.EmpresaId AND s.UnidadSerializadaId=u.UnidadSerializadaId
    WHERE i.CantidadSalida>0 AND i.TipoDocumentoOrigen NOT IN('TRASLADO','DEVOLUCION_PROVEEDOR','REVERSA_MOVIMIENTO');

    IF EXISTS
    (
        SELECT 1
        FROM inserted i JOIN inv.Articulo a ON a.EmpresaId=i.EmpresaId AND a.ArticuloId=i.ArticuloId AND a.ManejaSerial=1
        WHERE NOT (i.TipoDocumentoOrigen='RECEPCION_MERCANCIA' AND i.CantidadEntrada>0)
          AND i.TipoDocumentoOrigen<>'REVERSA_MOVIMIENTO'
          AND (SELECT COUNT(*) FROM @Asignadas x WHERE x.EmpresaId=i.EmpresaId AND x.MovimientoInventarioId=i.MovimientoInventarioId)
              <>CONVERT(int,COALESCE(NULLIF(i.CantidadEntrada,0),i.CantidadSalida))
    ) THROW 51982,'Debe asignar exactamente una unidad serializada por cada unidad del movimiento.',1;

    IF EXISTS
    (
        SELECT 1 FROM @Asignadas x
        JOIN inserted i ON i.EmpresaId=x.EmpresaId AND i.MovimientoInventarioId=x.MovimientoInventarioId
        JOIN inv.UnidadSerializada s ON s.EmpresaId=x.EmpresaId AND s.UnidadSerializadaId=x.UnidadSerializadaId
        WHERE s.ArticuloId<>i.ArticuloId OR
              (i.TipoMovimiento='TRASLADO_SALIDA' AND (s.Estado<>'DISPONIBLE' OR s.BodegaActualId<>i.BodegaId)) OR
              (i.TipoMovimiento='TRASLADO_ENTRADA_TRANSITO' AND (s.Estado<>'EN_TRANSITO' OR s.BodegaActualId<>i.BodegaId)) OR
              (i.TipoMovimiento='TRASLADO_SALIDA_TRANSITO' AND (s.Estado<>'EN_TRANSITO' OR s.BodegaActualId<>i.BodegaId)) OR
              (i.TipoMovimiento='TRASLADO_ENTRADA' AND s.Estado<>'EN_TRANSITO') OR
              (i.TipoDocumentoOrigen='DEVOLUCION_PROVEEDOR' AND (s.Estado<>'DISPONIBLE' OR s.BodegaActualId<>i.BodegaId)) OR
              (i.TipoDocumentoOrigen='DEVOLUCION_VENTA' AND s.Estado<>'VENDIDA') OR
              (i.CantidadSalida>0 AND i.TipoDocumentoOrigen NOT IN('TRASLADO','DEVOLUCION_PROVEEDOR','REVERSA_MOVIMIENTO') AND (s.Estado<>'DISPONIBLE' OR s.BodegaActualId<>i.BodegaId))
    ) THROW 51983,'Una unidad serializada no corresponde al articulo, estado o bodega del movimiento.',1;

    INSERT inv.MovimientoInventarioUnidad
    (EmpresaId,MovimientoInventarioId,UnidadSerializadaId,EstadoAnterior,EstadoPosterior,BodegaAnteriorId,BodegaPosteriorId,UbicacionAnteriorId,UbicacionPosteriorId)
    SELECT EmpresaId,MovimientoInventarioId,UnidadSerializadaId,EstadoAnterior,EstadoPosterior,BodegaAnteriorId,BodegaPosteriorId,UbicacionAnteriorId,UbicacionPosteriorId
    FROM @Asignadas;

    UPDATE s SET Estado=x.EstadoPosterior,BodegaActualId=x.BodegaPosteriorId,UbicacionActualId=x.UbicacionPosteriorId
    FROM inv.UnidadSerializada s
    JOIN @Asignadas x ON x.EmpresaId=s.EmpresaId AND x.UnidadSerializadaId=s.UnidadSerializadaId;

    UPDATE q SET Estado='CONSUMIDA',ConsumidoEnUtc=SYSUTCDATETIME()
    FROM inv.SolicitudSalidaSerializada q JOIN inserted i ON i.EmpresaId=q.EmpresaId AND i.IdempotencyKey=q.IdempotencyKey
    WHERE q.Estado='PENDIENTE';
END;
GO

CREATE OR ALTER TRIGGER inv.TR_Recepcion_MapearMovimientoUnidades ON inv.RecepcionMercancia AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    INSERT inv.MovimientoInventarioUnidad
    (EmpresaId,MovimientoInventarioId,UnidadSerializadaId,EstadoAnterior,EstadoPosterior,BodegaAnteriorId,BodegaPosteriorId,UbicacionAnteriorId,UbicacionPosteriorId)
    SELECT h.EmpresaId,m.MovimientoInventarioId,u.UnidadSerializadaId,NULL,'DISPONIBLE',NULL,h.BodegaId,NULL,l.UbicacionId
    FROM inserted h
    JOIN deleted d ON d.EmpresaId=h.EmpresaId AND d.RecepcionMercanciaId=h.RecepcionMercanciaId
    JOIN inv.RecepcionMercanciaLinea l ON l.EmpresaId=h.EmpresaId AND l.RecepcionMercanciaId=h.RecepcionMercanciaId
    JOIN inv.RecepcionMercanciaUnidad u ON u.EmpresaId=l.EmpresaId AND u.RecepcionMercanciaLineaId=l.RecepcionMercanciaLineaId AND u.UnidadSerializadaId IS NOT NULL
    JOIN inv.MovimientoInventario m ON m.EmpresaId=l.EmpresaId AND m.TipoDocumentoOrigen='RECEPCION_MERCANCIA' AND m.DocumentoOrigenId=h.RecepcionMercanciaId AND m.DocumentoLineaOrigenId=l.RecepcionMercanciaLineaId
    WHERE h.Estado='CONTABILIZADA' AND d.Estado<>'CONTABILIZADA'
      AND NOT EXISTS(SELECT 1 FROM inv.MovimientoInventarioUnidad x WHERE x.EmpresaId=m.EmpresaId AND x.MovimientoInventarioId=m.MovimientoInventarioId AND x.UnidadSerializadaId=u.UnidadSerializadaId);
END;
GO

EXEC sys.sp_settriggerorder @triggername=N'inv.TR_Recepcion_MapearMovimientoUnidades',@order=N'Last',@stmttype=N'UPDATE';
GO

CREATE OR ALTER PROCEDURE inv.usp_ContabilizarSalidaSerializada
    @EmpresaId bigint,@BodegaId bigint,@ArticuloId bigint,@PeriodoInventarioId bigint,
    @FechaMovimiento datetime2(7),@FechaContable date,@TipoMovimiento varchar(30),
    @ModuloOrigen varchar(30),@TipoDocumentoOrigen varchar(40),@DocumentoOrigenId bigint,
    @NumeroDocumento nvarchar(50),@CantidadSalida decimal(20,6),@IdempotencyKey uniqueidentifier,
    @UnidadesJson nvarchar(max),@UbicacionId bigint=NULL,@LoteId bigint=NULL,
    @DocumentoLineaOrigenId bigint=NULL,@TerceroId bigint=NULL,@UsuarioId bigint=NULL,
    @CorrelationId uniqueidentifier=NULL,@MovimientoRelacionadoId bigint=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF ISJSON(@UnidadesJson)<>1 THROW 51984,'Las unidades deben enviarse como un arreglo JSON valido.',1;
    IF NOT EXISTS(SELECT 1 FROM inv.Articulo WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId AND ManejaSerial=1)
        THROW 51985,'El articulo no esta configurado para manejo serializado.',1;
    IF @CantidadSalida<>FLOOR(@CantidadSalida) OR (SELECT COUNT(*) FROM OPENJSON(@UnidadesJson))<>CONVERT(int,@CantidadSalida)
        THROW 51986,'La cantidad y el numero de unidades serializadas no coinciden.',1;
    IF EXISTS(SELECT TRY_CONVERT(bigint,[value]) v FROM OPENJSON(@UnidadesJson) WHERE TRY_CONVERT(bigint,[value]) IS NULL)
        THROW 51987,'El arreglo contiene un identificador de unidad invalido.',1;
    IF (SELECT COUNT(DISTINCT TRY_CONVERT(bigint,[value])) FROM OPENJSON(@UnidadesJson))<>CONVERT(int,@CantidadSalida)
        THROW 51988,'Una unidad serializada esta repetida en la solicitud.',1;

    BEGIN TRANSACTION;
    DECLARE @SolicitudId bigint;
    SELECT @SolicitudId=SolicitudSalidaSerializadaId FROM inv.SolicitudSalidaSerializada WITH(UPDLOCK,HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND IdempotencyKey=@IdempotencyKey;
    IF @SolicitudId IS NULL
    BEGIN
        INSERT inv.SolicitudSalidaSerializada(EmpresaId,IdempotencyKey,ArticuloId,BodegaId)
        VALUES(@EmpresaId,@IdempotencyKey,@ArticuloId,@BodegaId);
        SET @SolicitudId=SCOPE_IDENTITY();
        INSERT inv.SolicitudSalidaSerializadaUnidad(EmpresaId,SolicitudSalidaSerializadaId,UnidadSerializadaId)
        SELECT @EmpresaId,@SolicitudId,TRY_CONVERT(bigint,[value]) FROM OPENJSON(@UnidadesJson);
    END
    ELSE IF EXISTS
    (
        SELECT TRY_CONVERT(bigint,[value]) UnidadId FROM OPENJSON(@UnidadesJson)
        EXCEPT
        SELECT UnidadSerializadaId FROM inv.SolicitudSalidaSerializadaUnidad WHERE EmpresaId=@EmpresaId AND SolicitudSalidaSerializadaId=@SolicitudId
    ) OR EXISTS
    (
        SELECT UnidadSerializadaId FROM inv.SolicitudSalidaSerializadaUnidad WHERE EmpresaId=@EmpresaId AND SolicitudSalidaSerializadaId=@SolicitudId
        EXCEPT
        SELECT TRY_CONVERT(bigint,[value]) FROM OPENJSON(@UnidadesJson)
    ) THROW 51989,'La clave idempotente ya fue usada con otras unidades.',1;

    EXEC inv.usp_ContabilizarSalida
        @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@UbicacionId=@UbicacionId,@ArticuloId=@ArticuloId,@LoteId=@LoteId,
        @PeriodoInventarioId=@PeriodoInventarioId,@FechaMovimiento=@FechaMovimiento,@FechaContable=@FechaContable,
        @TipoMovimiento=@TipoMovimiento,@ModuloOrigen=@ModuloOrigen,@TipoDocumentoOrigen=@TipoDocumentoOrigen,
        @DocumentoOrigenId=@DocumentoOrigenId,@DocumentoLineaOrigenId=@DocumentoLineaOrigenId,@NumeroDocumento=@NumeroDocumento,
        @TerceroId=@TerceroId,@CantidadSalida=@CantidadSalida,@IdempotencyKey=@IdempotencyKey,@UsuarioId=@UsuarioId,
        @CorrelationId=@CorrelationId,@MovimientoRelacionadoId=@MovimientoRelacionadoId;
    COMMIT;
END;
GO
