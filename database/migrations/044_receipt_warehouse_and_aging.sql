SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
IF COL_LENGTH('inv.RecepcionMercanciaLinea','BodegaId') IS NULL
BEGIN
    ALTER TABLE inv.RecepcionMercanciaLinea ADD BodegaId bigint NULL;
    ALTER TABLE inv.RecepcionMercanciaLinea ADD CONSTRAINT FK_RecepcionLinea_Bodega FOREIGN KEY(EmpresaId,BodegaId) REFERENCES inv.Bodega(EmpresaId,BodegaId);
    ALTER TABLE inv.TrasladoLinea ADD OrigenInventarioId bigint NULL;
    ALTER TABLE inv.TrasladoLinea ADD CONSTRAINT FK_TrasladoLinea_Origen FOREIGN KEY(EmpresaId,OrigenInventarioId) REFERENCES inv.OrigenInventario(EmpresaId,OrigenInventarioId);
    ALTER TABLE inv.Traslado ADD RecepcionMercanciaId bigint NULL,OperacionFacturaGuid uniqueidentifier NULL;
    ALTER TABLE inv.Traslado ADD CONSTRAINT FK_Traslado_Recepcion FOREIGN KEY(EmpresaId,RecepcionMercanciaId) REFERENCES inv.RecepcionMercancia(EmpresaId,RecepcionMercanciaId);
    EXEC(N'CREATE UNIQUE INDEX UX_Traslado_OperacionFactura ON inv.Traslado(EmpresaId,OperacionFacturaGuid,BodegaOrigenId) WHERE OperacionFacturaGuid IS NOT NULL;');
END;

    -- Extend the existing posting engine; preserve costing, audit, serial and AP hooks.
    DECLARE @sql nvarchar(max)=OBJECT_DEFINITION(OBJECT_ID('inv.usp_ContabilizarRecepcion'));
    IF CHARINDEX('@BodegasJson',@sql)=0
    BEGIN
    SET @sql=STUFF(@sql,1,CHARINDEX('PROCEDURE',@sql)-1,'ALTER ');
    SET @sql=REPLACE(@sql,'@CorrelationId uniqueidentifier=NULL','@CorrelationId uniqueidentifier=NULL, @BodegasJson nvarchar(max)=NULL');
    SET @sql=REPLACE(@sql,'DECLARE @LineaId bigint,','DECLARE @LineaBodega bigint; DECLARE @LineaId bigint,');
    SET @sql=REPLACE(@sql,'CantidadBase,CostoTotalCapitalizable,IdempotencyKey','CantidadBase,CostoTotalCapitalizable,IdempotencyKey,COALESCE(BodegaId,@BodegaId)');
    SET @sql=REPLACE(@sql,'@CantidadBase,@CostoTotal,@IdempotencyKey;','@CantidadBase,@CostoTotal,@IdempotencyKey,@LineaBodega;');
    SET @sql=REPLACE(@sql,'@BodegaId=@BodegaId,@UbicacionId','@BodegaId=@LineaBodega,@UbicacionId');
    SET @sql=REPLACE(@sql,'DECLARE @LineaBodega bigint;',N'
    IF @BodegasJson IS NOT NULL
    BEGIN
        IF ISJSON(@BodegasJson)<>1 THROW 51505,''Distribución de bodegas inválida.'',1;
        DECLARE @Asignacion TABLE(LineaId bigint,BodegaId bigint);
        INSERT @Asignacion SELECT LineaId,BodegaId FROM OPENJSON(@BodegasJson) WITH(LineaId bigint ''$.recepcionMercanciaLineaId'',BodegaId bigint ''$.bodegaId'');
        IF (SELECT COUNT(*) FROM @Asignacion)<>(SELECT COUNT(*) FROM inv.RecepcionMercanciaLinea WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionMercanciaId)
           OR EXISTS(SELECT LineaId FROM @Asignacion GROUP BY LineaId HAVING COUNT(*)>1)
           OR EXISTS(SELECT 1 FROM @Asignacion x LEFT JOIN inv.RecepcionMercanciaLinea l ON l.EmpresaId=@EmpresaId AND l.RecepcionMercanciaId=@RecepcionMercanciaId AND l.RecepcionMercanciaLineaId=x.LineaId LEFT JOIN inv.Bodega b ON b.EmpresaId=@EmpresaId AND b.BodegaId=x.BodegaId AND b.Activa=1 AND b.EsTransito=0 WHERE l.RecepcionMercanciaLineaId IS NULL OR b.BodegaId IS NULL)
            THROW 51506,''Asigna una bodega activa de la empresa a cada línea, sin duplicados.'',1;
        UPDATE l SET BodegaId=x.BodegaId,UbicacionId=CASE WHEN COALESCE(l.BodegaId,@BodegaId)=x.BodegaId THEN l.UbicacionId ELSE NULL END
        FROM inv.RecepcionMercanciaLinea l JOIN @Asignacion x ON x.LineaId=l.RecepcionMercanciaLineaId
        WHERE l.EmpresaId=@EmpresaId AND l.RecepcionMercanciaId=@RecepcionMercanciaId;
    END;
    IF EXISTS(SELECT 1 FROM inv.RecepcionMercanciaLinea l LEFT JOIN inv.Bodega b ON b.EmpresaId=l.EmpresaId AND b.BodegaId=COALESCE(l.BodegaId,@BodegaId) AND b.Activa=1 AND b.EsTransito=0 WHERE l.EmpresaId=@EmpresaId AND l.RecepcionMercanciaId=@RecepcionMercanciaId AND b.BodegaId IS NULL)
        THROW 51507,''La bodega de recepción no está activa o es de tránsito.'',1;
    DECLARE @LineaBodega bigint;');
    EXEC sys.sp_executesql @sql;
    END;

    SET @sql=OBJECT_DEFINITION(OBJECT_ID('inv.TR_Recepcion_CrearUnidadesSerializadas'));
    SET @sql=STUFF(@sql,1,CHARINDEX('TRIGGER',@sql)-1,'ALTER ');
    SET @sql=REPLACE(@sql,'l.LoteId,h.BodegaId,l.UbicacionId','l.LoteId,COALESCE(l.BodegaId,h.BodegaId),l.UbicacionId');
    EXEC sys.sp_executesql @sql;
    SET @sql=OBJECT_DEFINITION(OBJECT_ID('inv.TR_Recepcion_MapearMovimientoUnidades'));
    SET @sql=STUFF(@sql,1,CHARINDEX('TRIGGER',@sql)-1,'ALTER ');
    SET @sql=REPLACE(@sql,'NULL,h.BodegaId,NULL,l.UbicacionId','NULL,m.BodegaId,NULL,l.UbicacionId');
    EXEC sys.sp_executesql @sql;
    EXEC sys.sp_settriggerorder @triggername=N'inv.TR_Recepcion_MapearMovimientoUnidades',@order=N'Last',@stmttype=N'UPDATE';

    -- Invoice transfers consume their exact origin, never another purchase of the same SKU.
    SET @sql=OBJECT_DEFINITION(OBJECT_ID('inv.TR_MovimientoInventario_Origenes'));
    IF CHARINDEX('@UnidadesOrigen',@sql)=0
    BEGIN
    SET @sql=STUFF(@sql,1,CHARINDEX('TRIGGER',@sql)-1,'ALTER ');
    SET @sql=REPLACE(@sql,'DECLARE origenes CURSOR',N'
            IF @TipoDocumento=''TRASLADO''
                SELECT @RecepcionLineaId=o.RecepcionMercanciaLineaId FROM inv.TrasladoLinea t JOIN inv.OrigenInventario o ON o.EmpresaId=t.EmpresaId AND o.OrigenInventarioId=t.OrigenInventarioId WHERE t.EmpresaId=@EmpresaId AND t.TrasladoLineaId=@DocumentoLineaId;
            DECLARE origenes CURSOR');
    SET @sql=REPLACE(@sql,'DECLARE origenes CURSOR',N'
            DECLARE @Serial bit=(SELECT ManejaSerial FROM inv.Articulo WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId);
            DECLARE @UnidadesOrigen TABLE(LineaId bigint,Cantidad decimal(20,6));
            DELETE FROM @UnidadesOrigen;
            IF @Serial=1
                INSERT @UnidadesOrigen
                SELECT ru.RecepcionMercanciaLineaId,COUNT(*) FROM inv.RecepcionMercanciaUnidad ru
                WHERE ru.EmpresaId=@EmpresaId AND ru.UnidadSerializadaId IN
                (
                    SELECT UnidadSerializadaId FROM inv.TrasladoLineaUnidad WHERE EmpresaId=@EmpresaId AND TrasladoLineaId=@DocumentoLineaId AND @TipoDocumento=''TRASLADO''
                    UNION
                    SELECT UnidadSerializadaId FROM inv.DevolucionProveedorLineaUnidad WHERE EmpresaId=@EmpresaId AND DevolucionProveedorLineaId=@DocumentoLineaId AND @TipoDocumento=''DEVOLUCION_PROVEEDOR''
                    UNION
                    SELECT u.UnidadSerializadaId FROM inv.SolicitudSalidaSerializada q JOIN inv.SolicitudSalidaSerializadaUnidad u ON u.EmpresaId=q.EmpresaId AND u.SolicitudSalidaSerializadaId=q.SolicitudSalidaSerializadaId JOIN inserted i ON i.EmpresaId=q.EmpresaId AND i.IdempotencyKey=q.IdempotencyKey WHERE i.MovimientoInventarioId=@MovimientoId
                ) GROUP BY ru.RecepcionMercanciaLineaId;
            DECLARE origenes CURSOR');
    SET @sql=REPLACE(@sql,'SELECT s.OrigenInventarioId,s.CantidadDisponible',N'SELECT s.OrigenInventarioId,CASE WHEN @Serial=1 THEN (SELECT Cantidad FROM @UnidadesOrigen WHERE LineaId=o.RecepcionMercanciaLineaId) ELSE s.CantidadDisponible END');
    SET @sql=REPLACE(@sql,'AND (@RecepcionLineaId IS NULL OR o.RecepcionMercanciaLineaId=@RecepcionLineaId)',N'AND (@RecepcionLineaId IS NULL OR o.RecepcionMercanciaLineaId=@RecepcionLineaId) AND (@Serial=0 OR EXISTS(SELECT 1 FROM @UnidadesOrigen u WHERE u.LineaId=o.RecepcionMercanciaLineaId AND u.Cantidad<=s.CantidadDisponible))');
    EXEC sys.sp_executesql @sql;
    END;
GO

CREATE OR ALTER PROCEDURE inv.usp_TrasladarFactura
    @EmpresaId bigint,@RecepcionMercanciaId bigint,@BodegaDestinoId bigint,
    @PeriodoInventarioId bigint,@FechaContable date,@OperacionGuid uniqueidentifier,@UsuarioId bigint,
    @Traslados int OUTPUT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    DECLARE @Estado varchar(15),@FechaEntrada date;
    SELECT @Estado=Estado,@FechaEntrada=FechaContable FROM inv.RecepcionMercancia WITH(UPDLOCK,HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionMercanciaId;
    IF @Estado IS NULL OR @Estado<>'CONTABILIZADA' THROW 51520,'Solo se pueden trasladar entradas contabilizadas de esta empresa.',1;
    IF @OperacionGuid IS NULL THROW 51521,'Falta el identificador de la operación.',1;
    IF EXISTS(SELECT 1 FROM inv.Traslado WHERE EmpresaId=@EmpresaId AND OperacionFacturaGuid=@OperacionGuid)
    BEGIN
        IF EXISTS(SELECT 1 FROM inv.Traslado WHERE EmpresaId=@EmpresaId AND OperacionFacturaGuid=@OperacionGuid AND (RecepcionMercanciaId<>@RecepcionMercanciaId OR BodegaDestinoId<>@BodegaDestinoId OR FechaContableSalida<>@FechaContable OR PeriodoSalidaId<>@PeriodoInventarioId)) THROW 51522,'El identificador ya fue usado para otro traslado.',1;
        SELECT @Traslados=COUNT(*) FROM inv.Traslado WHERE EmpresaId=@EmpresaId AND OperacionFacturaGuid=@OperacionGuid;
        COMMIT; RETURN;
    END;
    IF @FechaContable<@FechaEntrada THROW 51523,'La fecha del traslado no puede preceder la entrada.',1;
    IF NOT EXISTS(SELECT 1 FROM inv.Bodega WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaDestinoId AND Activa=1 AND EsTransito=0) THROW 51524,'Selecciona una bodega destino activa, no de tránsito.',1;
    IF NOT EXISTS(SELECT 1 FROM core.PeriodoInventario WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoInventarioId AND Estado IN('ABIERTO','REABIERTO') AND @FechaContable BETWEEN FechaInicio AND FechaFin) THROW 51525,'El periodo no está abierto o no corresponde a la fecha.',1;

    DECLARE @S TABLE(OrigenId bigint,LineaId bigint,BodegaId bigint,ArticuloId bigint,LoteId bigint,Cantidad decimal(20,6));
    INSERT @S
    SELECT o.OrigenInventarioId,l.RecepcionMercanciaLineaId,s.BodegaId,l.ArticuloId,l.LoteId,s.CantidadDisponible
    FROM inv.RecepcionMercanciaLinea l
    JOIN inv.OrigenInventario o ON o.EmpresaId=l.EmpresaId AND o.RecepcionMercanciaLineaId=l.RecepcionMercanciaLineaId
    JOIN inv.SaldoOrigenBodega s WITH(UPDLOCK,HOLDLOCK) ON s.EmpresaId=o.EmpresaId AND s.OrigenInventarioId=o.OrigenInventarioId
    WHERE l.EmpresaId=@EmpresaId AND l.RecepcionMercanciaId=@RecepcionMercanciaId AND s.CantidadDisponible>0;
    IF EXISTS(SELECT 1 FROM inv.RecepcionMercanciaLinea l WHERE l.EmpresaId=@EmpresaId AND l.RecepcionMercanciaId=@RecepcionMercanciaId AND l.CantidadBase<>COALESCE((SELECT SUM(Cantidad) FROM @S WHERE LineaId=l.RecepcionMercanciaLineaId),0))
        THROW 51526,'No está disponible toda la mercancía de la factura. Hay unidades vendidas, devueltas, en tránsito o consumidas. No se realizó ningún traslado.',1;
    IF EXISTS(SELECT 1 FROM @S s JOIN inv.Bodega b ON b.EmpresaId=@EmpresaId AND b.BodegaId=s.BodegaId WHERE b.EsTransito=1 OR b.Activa=0)
        THROW 51527,'Hay mercancía en tránsito o en una bodega inactiva.',1;
    IF EXISTS(SELECT 1 FROM @S s JOIN inv.Articulo a ON a.EmpresaId=@EmpresaId AND a.ArticuloId=s.ArticuloId AND a.ManejaSerial=1 WHERE s.Cantidad<>(SELECT COUNT(*) FROM inv.RecepcionMercanciaUnidad ru JOIN inv.UnidadSerializada u WITH(UPDLOCK,HOLDLOCK) ON u.EmpresaId=ru.EmpresaId AND u.UnidadSerializadaId=ru.UnidadSerializadaId WHERE ru.EmpresaId=@EmpresaId AND ru.RecepcionMercanciaLineaId=s.LineaId AND u.BodegaActualId=s.BodegaId AND u.Estado='DISPONIBLE'))
        THROW 51528,'Las unidades serializadas no están todas disponibles en su bodega de origen. No se trasladó la factura.',1;

    SET @Traslados=0;
    DECLARE @Origen bigint,@Id bigint,@Numero nvarchar(50),@Fecha datetime2(7)=CONVERT(datetime2(7),@FechaContable);
    DECLARE bodegas CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT BodegaId FROM @S WHERE BodegaId<>@BodegaDestinoId ORDER BY BodegaId;
    OPEN bodegas; FETCH NEXT FROM bodegas INTO @Origen;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @Numero=CONCAT('TF-',LEFT(CONVERT(varchar(36),@OperacionGuid),28),'-',@Origen);
        INSERT inv.Traslado(EmpresaId,Numero,BodegaOrigenId,BodegaDestinoId,FechaSalida,CreadoPorUsuarioId,RecepcionMercanciaId,OperacionFacturaGuid)
        VALUES(@EmpresaId,@Numero,@Origen,@BodegaDestinoId,@Fecha,@UsuarioId,@RecepcionMercanciaId,@OperacionGuid);
        SET @Id=SCOPE_IDENTITY();
        INSERT inv.TrasladoLinea(EmpresaId,TrasladoId,NumeroLinea,ArticuloId,CantidadDespachada,LoteId,OrigenInventarioId)
        SELECT @EmpresaId,@Id,ROW_NUMBER() OVER(ORDER BY ArticuloId,OrigenId),ArticuloId,Cantidad,LoteId,OrigenId FROM @S WHERE BodegaId=@Origen;
        INSERT inv.TrasladoLineaUnidad(EmpresaId,TrasladoLineaId,UnidadSerializadaId)
        SELECT @EmpresaId,t.TrasladoLineaId,u.UnidadSerializadaId FROM inv.TrasladoLinea t
        JOIN @S s ON s.OrigenId=t.OrigenInventarioId AND s.BodegaId=@Origen
        JOIN inv.RecepcionMercanciaUnidad ru ON ru.EmpresaId=@EmpresaId AND ru.RecepcionMercanciaLineaId=s.LineaId
        JOIN inv.UnidadSerializada u ON u.EmpresaId=ru.EmpresaId AND u.UnidadSerializadaId=ru.UnidadSerializadaId AND u.BodegaActualId=@Origen AND u.Estado='DISPONIBLE'
        WHERE t.EmpresaId=@EmpresaId AND t.TrasladoId=@Id;
        EXEC inv.usp_DespacharTraslado @EmpresaId=@EmpresaId,@TrasladoId=@Id,@PeriodoInventarioId=@PeriodoInventarioId,@FechaContable=@FechaContable,@UsuarioId=@UsuarioId,@CorrelationId=@OperacionGuid;
        EXEC inv.usp_RecibirTraslado @EmpresaId=@EmpresaId,@TrasladoId=@Id,@PeriodoInventarioId=@PeriodoInventarioId,@FechaContable=@FechaContable,@FechaRecepcion=@Fecha,@UsuarioId=@UsuarioId,@CorrelationId=@OperacionGuid;
        SET @Traslados+=1;
        FETCH NEXT FROM bodegas INTO @Origen;
    END;
    CLOSE bodegas; DEALLOCATE bodegas;
    COMMIT;
END;
GO
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='044_receipt_warehouse_and_aging')
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('044_receipt_warehouse_and_aging',N'Bodega por línea, traslado completo por origen y consulta de antigüedad');
IF COALESCE(CHARINDEX('@BodegasJson',OBJECT_DEFINITION(OBJECT_ID('inv.usp_ContabilizarRecepcion'))),0)=0
   OR COALESCE(CHARINDEX('@BodegaId=@LineaBodega',OBJECT_DEFINITION(OBJECT_ID('inv.usp_ContabilizarRecepcion'))),0)=0
   OR COALESCE(CHARINDEX('@UnidadesOrigen',OBJECT_DEFINITION(OBJECT_ID('inv.TR_MovimientoInventario_Origenes'))),0)=0
    THROW 51529,'No fue posible verificar la extensión de los procedimientos de inventario.',1;
COMMIT;
GO
