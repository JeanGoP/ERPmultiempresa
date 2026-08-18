SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='019_inventory_origin_trace')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
    CREATE TABLE inv.OrigenInventario
    (
        OrigenInventarioId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        ArticuloId bigint NOT NULL,
        OrigenClave nvarchar(300) NOT NULL,
        TipoOrigen varchar(40) NOT NULL,
        DocumentoOrigenId bigint NULL,
        DocumentoLineaOrigenId bigint NULL,
        RecepcionMercanciaLineaId bigint NULL,
        MovimientoEntradaInicialId bigint NULL,
        CreadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_OrigenInventario_Fecha DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_OrigenInventario PRIMARY KEY CLUSTERED(OrigenInventarioId),
        CONSTRAINT UQ_OrigenInventario_EmpresaId UNIQUE(EmpresaId,OrigenInventarioId),
        CONSTRAINT UQ_OrigenInventario_Clave UNIQUE(EmpresaId,OrigenClave),
        CONSTRAINT FK_OrigenInventario_Articulo FOREIGN KEY(EmpresaId,ArticuloId) REFERENCES inv.Articulo(EmpresaId,ArticuloId),
        CONSTRAINT FK_OrigenInventario_RecepcionLinea FOREIGN KEY(EmpresaId,RecepcionMercanciaLineaId) REFERENCES inv.RecepcionMercanciaLinea(EmpresaId,RecepcionMercanciaLineaId),
        CONSTRAINT FK_OrigenInventario_Movimiento FOREIGN KEY(EmpresaId,MovimientoEntradaInicialId) REFERENCES inv.MovimientoInventario(EmpresaId,MovimientoInventarioId)
    );
    CREATE TABLE inv.SaldoOrigenBodega
    (
        EmpresaId bigint NOT NULL,
        BodegaId bigint NOT NULL,
        ArticuloId bigint NOT NULL,
        OrigenInventarioId bigint NOT NULL,
        CantidadDisponible decimal(20,6) NOT NULL,
        ActualizadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_SaldoOrigen_Fecha DEFAULT SYSUTCDATETIME(),
        RowVersion rowversion NOT NULL,
        CONSTRAINT PK_SaldoOrigenBodega PRIMARY KEY CLUSTERED(EmpresaId,BodegaId,ArticuloId,OrigenInventarioId),
        CONSTRAINT FK_SaldoOrigenBodega_Bodega FOREIGN KEY(EmpresaId,BodegaId) REFERENCES inv.Bodega(EmpresaId,BodegaId),
        CONSTRAINT FK_SaldoOrigenBodega_Articulo FOREIGN KEY(EmpresaId,ArticuloId) REFERENCES inv.Articulo(EmpresaId,ArticuloId),
        CONSTRAINT FK_SaldoOrigenBodega_Origen FOREIGN KEY(EmpresaId,OrigenInventarioId) REFERENCES inv.OrigenInventario(EmpresaId,OrigenInventarioId),
        CONSTRAINT CK_SaldoOrigenBodega_Cantidad CHECK(CantidadDisponible>=0)
    );
    CREATE TABLE inv.MovimientoOrigenInventario
    (
        MovimientoOrigenInventarioId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        MovimientoInventarioId bigint NOT NULL,
        OrigenInventarioId bigint NOT NULL,
        CantidadEntrada decimal(20,6) NOT NULL CONSTRAINT DF_MovimientoOrigen_Entrada DEFAULT 0,
        CantidadSalida decimal(20,6) NOT NULL CONSTRAINT DF_MovimientoOrigen_Salida DEFAULT 0,
        CreadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_MovimientoOrigen_Fecha DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_MovimientoOrigenInventario PRIMARY KEY CLUSTERED(MovimientoOrigenInventarioId),
        CONSTRAINT UQ_MovimientoOrigenInventario UNIQUE(EmpresaId,MovimientoInventarioId,OrigenInventarioId),
        CONSTRAINT FK_MovimientoOrigenInventario_Movimiento FOREIGN KEY(EmpresaId,MovimientoInventarioId) REFERENCES inv.MovimientoInventario(EmpresaId,MovimientoInventarioId),
        CONSTRAINT FK_MovimientoOrigenInventario_Origen FOREIGN KEY(EmpresaId,OrigenInventarioId) REFERENCES inv.OrigenInventario(EmpresaId,OrigenInventarioId),
        CONSTRAINT CK_MovimientoOrigenInventario_Cantidad CHECK((CantidadEntrada>0 AND CantidadSalida=0) OR (CantidadSalida>0 AND CantidadEntrada=0))
    );
    CREATE INDEX IX_OrigenInventario_Recepcion ON inv.OrigenInventario(EmpresaId,RecepcionMercanciaLineaId) WHERE RecepcionMercanciaLineaId IS NOT NULL;
    CREATE INDEX IX_MovimientoOrigen_Origen ON inv.MovimientoOrigenInventario(EmpresaId,OrigenInventarioId,MovimientoInventarioId) INCLUDE(CantidadEntrada,CantidadSalida);

    INSERT inv.OrigenInventario(EmpresaId,ArticuloId,OrigenClave,TipoOrigen,MovimientoEntradaInicialId)
    SELECT s.EmpresaId,s.ArticuloId,CONCAT(N'LEGACY:',s.BodegaId,N':',s.ArticuloId),N'MIGRACION_SALDO',s.UltimoMovimientoId
    FROM inv.SaldoArticuloBodega s WHERE s.Existencia>0;
    INSERT inv.SaldoOrigenBodega(EmpresaId,BodegaId,ArticuloId,OrigenInventarioId,CantidadDisponible)
    SELECT s.EmpresaId,s.BodegaId,s.ArticuloId,o.OrigenInventarioId,s.Existencia
    FROM inv.SaldoArticuloBodega s JOIN inv.OrigenInventario o ON o.EmpresaId=s.EmpresaId AND o.OrigenClave=CONCAT(N'LEGACY:',s.BodegaId,N':',s.ArticuloId)
    WHERE s.Existencia>0;

    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.OrigenInventario;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.OrigenInventario AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.SaldoOrigenBodega;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.SaldoOrigenBodega AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.SaldoOrigenBodega AFTER UPDATE;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.MovimientoOrigenInventario;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.MovimientoOrigenInventario AFTER INSERT;');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('019_inventory_origin_trace',N'Trazabilidad de origen de existencias independiente de la fórmula de valoración');
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO

CREATE OR ALTER TRIGGER inv.TR_MovimientoInventario_Origenes ON inv.MovimientoInventario AFTER INSERT AS
BEGIN
    SET NOCOUNT ON;
    IF TRY_CONVERT(bit,SESSION_CONTEXT(N'OmitirOrigenAutomatico'))=1 RETURN;
    DECLARE @EmpresaId bigint,@MovimientoId bigint,@BodegaId bigint,@ArticuloId bigint,@Entrada decimal(20,6),@Salida decimal(20,6),
            @TipoDocumento varchar(40),@DocumentoId bigint,@DocumentoLineaId bigint,@RelacionadoId bigint,@OrigenId bigint,@Cantidad decimal(20,6),
            @Restante decimal(20,6),@Disponible decimal(20,6),@RecepcionLineaId bigint,@Clave nvarchar(300);
    DECLARE movimientos CURSOR LOCAL FAST_FORWARD FOR
        SELECT EmpresaId,MovimientoInventarioId,BodegaId,ArticuloId,CantidadEntrada,CantidadSalida,TipoDocumentoOrigen,DocumentoOrigenId,DocumentoLineaOrigenId,MovimientoRelacionadoId
        FROM inserted WHERE CantidadEntrada>0 OR CantidadSalida>0 ORDER BY MovimientoInventarioId;
    OPEN movimientos;
    FETCH NEXT FROM movimientos INTO @EmpresaId,@MovimientoId,@BodegaId,@ArticuloId,@Entrada,@Salida,@TipoDocumento,@DocumentoId,@DocumentoLineaId,@RelacionadoId;
    WHILE @@FETCH_STATUS=0
    BEGIN
        IF @Entrada>0
        BEGIN
            SET @Restante=@Entrada;
            IF @RelacionadoId IS NOT NULL AND EXISTS(SELECT 1 FROM inv.MovimientoOrigenInventario WHERE EmpresaId=@EmpresaId AND MovimientoInventarioId=@RelacionadoId AND CantidadSalida>0)
            BEGIN
                DECLARE relacionados CURSOR LOCAL FAST_FORWARD FOR
                    SELECT original.OrigenInventarioId,original.CantidadSalida-COALESCE(devuelta.Cantidad,0)
                    FROM inv.MovimientoOrigenInventario original
                    OUTER APPLY
                    (
                        SELECT SUM(retorno.CantidadEntrada) Cantidad
                        FROM inv.MovimientoInventario m
                        JOIN inv.MovimientoOrigenInventario retorno ON retorno.EmpresaId=m.EmpresaId AND retorno.MovimientoInventarioId=m.MovimientoInventarioId AND retorno.OrigenInventarioId=original.OrigenInventarioId
                        WHERE m.EmpresaId=@EmpresaId AND m.MovimientoRelacionadoId=@RelacionadoId AND retorno.CantidadEntrada>0
                    ) devuelta
                    WHERE original.EmpresaId=@EmpresaId AND original.MovimientoInventarioId=@RelacionadoId AND original.CantidadSalida>COALESCE(devuelta.Cantidad,0)
                    ORDER BY original.MovimientoOrigenInventarioId;
                OPEN relacionados; FETCH NEXT FROM relacionados INTO @OrigenId,@Disponible;
                WHILE @@FETCH_STATUS=0 AND @Restante>0
                BEGIN
                    SET @Cantidad=CASE WHEN @Disponible<@Restante THEN @Disponible ELSE @Restante END;
                    UPDATE inv.SaldoOrigenBodega SET CantidadDisponible=CantidadDisponible+@Cantidad,ActualizadoEnUtc=SYSUTCDATETIME()
                    WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId AND OrigenInventarioId=@OrigenId;
                    IF @@ROWCOUNT=0 INSERT inv.SaldoOrigenBodega(EmpresaId,BodegaId,ArticuloId,OrigenInventarioId,CantidadDisponible) VALUES(@EmpresaId,@BodegaId,@ArticuloId,@OrigenId,@Cantidad);
                    INSERT inv.MovimientoOrigenInventario(EmpresaId,MovimientoInventarioId,OrigenInventarioId,CantidadEntrada) VALUES(@EmpresaId,@MovimientoId,@OrigenId,@Cantidad);
                    SET @Restante-=@Cantidad;
                    FETCH NEXT FROM relacionados INTO @OrigenId,@Disponible;
                END;
                CLOSE relacionados; DEALLOCATE relacionados;
                IF @Restante>0 THROW 51941,'La entrada relacionada supera la cantidad reversible del movimiento original.',1;
            END;
            ELSE IF @RelacionadoId IS NOT NULL
                THROW 51942,'El movimiento relacionado no contiene trazabilidad de salida reversible.',1;
            ELSE IF @Restante>0
            BEGIN
                SET @RecepcionLineaId=CASE WHEN @TipoDocumento='RECEPCION_MERCANCIA' THEN @DocumentoLineaId ELSE NULL END;
                SET @Clave=CONCAT(@TipoDocumento,N':',@DocumentoId,N':',COALESCE(CONVERT(varchar(30),@DocumentoLineaId),'0'),N':',@ArticuloId);
                SELECT @OrigenId=OrigenInventarioId FROM inv.OrigenInventario WHERE EmpresaId=@EmpresaId AND OrigenClave=@Clave;
                IF @OrigenId IS NULL
                BEGIN
                    INSERT inv.OrigenInventario(EmpresaId,ArticuloId,OrigenClave,TipoOrigen,DocumentoOrigenId,DocumentoLineaOrigenId,RecepcionMercanciaLineaId,MovimientoEntradaInicialId)
                    VALUES(@EmpresaId,@ArticuloId,@Clave,@TipoDocumento,@DocumentoId,@DocumentoLineaId,@RecepcionLineaId,@MovimientoId);
                    SET @OrigenId=SCOPE_IDENTITY();
                END;
                UPDATE inv.SaldoOrigenBodega SET CantidadDisponible=CantidadDisponible+@Restante,ActualizadoEnUtc=SYSUTCDATETIME()
                WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId AND OrigenInventarioId=@OrigenId;
                IF @@ROWCOUNT=0 INSERT inv.SaldoOrigenBodega(EmpresaId,BodegaId,ArticuloId,OrigenInventarioId,CantidadDisponible) VALUES(@EmpresaId,@BodegaId,@ArticuloId,@OrigenId,@Restante);
                INSERT inv.MovimientoOrigenInventario(EmpresaId,MovimientoInventarioId,OrigenInventarioId,CantidadEntrada) VALUES(@EmpresaId,@MovimientoId,@OrigenId,@Restante);
            END;
        END
        ELSE IF @Salida>0
        BEGIN
            SET @Restante=@Salida;
            SET @RecepcionLineaId=NULL;
            IF @TipoDocumento='DEVOLUCION_PROVEEDOR'
                SELECT @RecepcionLineaId=RecepcionMercanciaLineaId FROM inv.DevolucionProveedorLinea WHERE EmpresaId=@EmpresaId AND DevolucionProveedorLineaId=@DocumentoLineaId;
            DECLARE origenes CURSOR LOCAL FAST_FORWARD FOR
                SELECT s.OrigenInventarioId,s.CantidadDisponible
                FROM inv.SaldoOrigenBodega s WITH(UPDLOCK,HOLDLOCK)
                JOIN inv.OrigenInventario o ON o.EmpresaId=s.EmpresaId AND o.OrigenInventarioId=s.OrigenInventarioId
                WHERE s.EmpresaId=@EmpresaId AND s.BodegaId=@BodegaId AND s.ArticuloId=@ArticuloId AND s.CantidadDisponible>0
                  AND (@RecepcionLineaId IS NULL OR o.RecepcionMercanciaLineaId=@RecepcionLineaId)
                ORDER BY o.OrigenInventarioId;
            OPEN origenes; FETCH NEXT FROM origenes INTO @OrigenId,@Disponible;
            WHILE @@FETCH_STATUS=0 AND @Restante>0
            BEGIN
                SET @Cantidad=CASE WHEN @Disponible<@Restante THEN @Disponible ELSE @Restante END;
                UPDATE inv.SaldoOrigenBodega SET CantidadDisponible=CantidadDisponible-@Cantidad,ActualizadoEnUtc=SYSUTCDATETIME()
                WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId AND OrigenInventarioId=@OrigenId;
                INSERT inv.MovimientoOrigenInventario(EmpresaId,MovimientoInventarioId,OrigenInventarioId,CantidadSalida) VALUES(@EmpresaId,@MovimientoId,@OrigenId,@Cantidad);
                SET @Restante-=@Cantidad;
                FETCH NEXT FROM origenes INTO @OrigenId,@Disponible;
            END;
            CLOSE origenes; DEALLOCATE origenes;
            IF @Restante>0 THROW 51940,'La salida no puede atribuirse completamente a existencias de origen disponibles.',1;
        END;
        SET @OrigenId=NULL; SET @RecepcionLineaId=NULL;
        FETCH NEXT FROM movimientos INTO @EmpresaId,@MovimientoId,@BodegaId,@ArticuloId,@Entrada,@Salida,@TipoDocumento,@DocumentoId,@DocumentoLineaId,@RelacionadoId;
    END;
    CLOSE movimientos; DEALLOCATE movimientos;
END;
GO
