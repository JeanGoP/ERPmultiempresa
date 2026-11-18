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

BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='093_purchase_entry_reversal')
BEGIN
    CREATE TABLE inv.ReversionEntradaMercancia
    (
        ReversionEntradaMercanciaId bigint IDENTITY(1,1) NOT NULL PRIMARY KEY,
        EmpresaId bigint NOT NULL,
        RecepcionMercanciaId bigint NOT NULL,
        DocumentoProveedorId bigint NOT NULL,
        PeriodoInventarioId bigint NOT NULL,
        PeriodoContableId bigint NULL,
        FechaContable date NOT NULL,
        Motivo nvarchar(500) NOT NULL,
        OperacionGuid uniqueidentifier NOT NULL DEFAULT NEWID(),
        Estado varchar(20) NOT NULL DEFAULT 'CONTABILIZADA',
        CreadoPorUsuarioId bigint NULL REFERENCES seg.Usuario(UsuarioId),
        CreadoEnUtc datetime2(7) NOT NULL DEFAULT SYSUTCDATETIME(),
        ComprobanteOriginalId bigint NULL,
        ComprobanteReversionId bigint NULL,
        ZeusEstado varchar(25) NOT NULL DEFAULT 'SIN_ENVIO',
        ZeusSnapshotOriginal nvarchar(max) NULL,
        ZeusSnapshot nvarchar(max) NULL,
        ZeusFuente varchar(2) NULL,
        ZeusDocumento varchar(20) NULL,
        ZeusError nvarchar(2000) NULL,
        ZeusIntentos int NOT NULL DEFAULT 0,
        ZeusActualizadoEnUtc datetime2(7) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_ReversionEntrada_Empresa UNIQUE(EmpresaId,ReversionEntradaMercanciaId),
        CONSTRAINT UQ_ReversionEntrada_Recepcion UNIQUE(EmpresaId,RecepcionMercanciaId),
        CONSTRAINT UQ_ReversionEntrada_Operacion UNIQUE(OperacionGuid),
        CONSTRAINT FK_ReversionEntrada_Recepcion FOREIGN KEY(EmpresaId,RecepcionMercanciaId) REFERENCES inv.RecepcionMercancia(EmpresaId,RecepcionMercanciaId),
        CONSTRAINT FK_ReversionEntrada_Documento FOREIGN KEY(EmpresaId,DocumentoProveedorId) REFERENCES comp.DocumentoProveedor(EmpresaId,DocumentoProveedorId),
        CONSTRAINT FK_ReversionEntrada_Periodo FOREIGN KEY(EmpresaId,PeriodoInventarioId) REFERENCES core.PeriodoInventario(EmpresaId,PeriodoInventarioId),
        CONSTRAINT FK_ReversionEntrada_PeriodoContable FOREIGN KEY(EmpresaId,PeriodoContableId) REFERENCES core.PeriodoContable(EmpresaId,PeriodoContableId),
        CONSTRAINT FK_ReversionEntrada_Comprobante FOREIGN KEY(EmpresaId,ComprobanteOriginalId) REFERENCES cont.ComprobanteContable(EmpresaId,ComprobanteContableId),
        CONSTRAINT FK_ReversionEntrada_ComprobanteReversion FOREIGN KEY(EmpresaId,ComprobanteReversionId) REFERENCES cont.ComprobanteContable(EmpresaId,ComprobanteContableId),
        CONSTRAINT CK_ReversionEntrada_Motivo CHECK(LEN(LTRIM(RTRIM(Motivo)))>=10),
        CONSTRAINT CK_ReversionEntrada_Estado CHECK(Estado='CONTABILIZADA'),
        CONSTRAINT CK_ReversionEntrada_Zeus CHECK(ZeusEstado IN('SIN_ENVIO','PENDIENTE','ENVIANDO','INCIERTO','CONTABILIZADO','RECHAZADO')),
        CONSTRAINT CK_ReversionEntrada_OriginalJson CHECK(ZeusSnapshotOriginal IS NULL OR ISJSON(ZeusSnapshotOriginal)=1),
        CONSTRAINT CK_ReversionEntrada_Json CHECK(ZeusSnapshot IS NULL OR ISJSON(ZeusSnapshot)=1)
    );
    CREATE INDEX IX_ReversionEntrada_Cola ON inv.ReversionEntradaMercancia(ZeusEstado,ZeusActualizadoEnUtc)
        INCLUDE(EmpresaId,RecepcionMercanciaId);
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy
        ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.ReversionEntradaMercancia,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.ReversionEntradaMercancia AFTER INSERT,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.ReversionEntradaMercancia AFTER UPDATE;');
    ALTER TABLE core.ZeusEnvio DROP CONSTRAINT CK_ZeusEnvio_Estado;
    ALTER TABLE core.ZeusEnvio ADD CONSTRAINT CK_ZeusEnvio_Estado
        CHECK(Estado IN('REQUIERE_REVISION','PENDIENTE','ENVIANDO','CONTABILIZADO','RECHAZADO','INCIERTO','CANCELADO'));
END;
GO

CREATE OR ALTER TRIGGER inv.TR_Recepcion_CrearUnidadesSerializadas ON inv.RecepcionMercancia AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.EmpresaId=i.EmpresaId AND d.RecepcionMercanciaId=i.RecepcionMercanciaId
        WHERE i.Estado='CONTABILIZADA' AND d.Estado<>'CONTABILIZADA') RETURN;
    IF EXISTS(
        SELECT 1 FROM inserted h
        JOIN deleted d ON d.EmpresaId=h.EmpresaId AND d.RecepcionMercanciaId=h.RecepcionMercanciaId
        JOIN inv.RecepcionMercanciaLinea l ON l.EmpresaId=h.EmpresaId AND l.RecepcionMercanciaId=h.RecepcionMercanciaId
        JOIN inv.Articulo a ON a.EmpresaId=l.EmpresaId AND a.ArticuloId=l.ArticuloId
        OUTER APPLY(SELECT COUNT(*) Cantidad FROM inv.RecepcionMercanciaUnidad u
            WHERE u.EmpresaId=l.EmpresaId AND u.RecepcionMercanciaLineaId=l.RecepcionMercanciaLineaId) x
        WHERE h.Estado='CONTABILIZADA' AND d.Estado<>'CONTABILIZADA' AND a.ManejaSerial=1
            AND (l.CantidadBase<>FLOOR(l.CantidadBase) OR x.Cantidad<>CONVERT(int,l.CantidadBase))
    ) THROW 51894,'La cantidad de seriales, motores o chasis no coincide con las unidades recibidas del artículo serializado.',1;
    IF EXISTS(
        SELECT 1 FROM inserted h
        JOIN deleted d ON d.EmpresaId=h.EmpresaId AND d.RecepcionMercanciaId=h.RecepcionMercanciaId
        JOIN inv.RecepcionMercanciaLinea l ON l.EmpresaId=h.EmpresaId AND l.RecepcionMercanciaId=h.RecepcionMercanciaId
        JOIN inv.Articulo a ON a.EmpresaId=l.EmpresaId AND a.ArticuloId=l.ArticuloId
        JOIN inv.RecepcionMercanciaUnidad u ON u.EmpresaId=l.EmpresaId AND u.RecepcionMercanciaLineaId=l.RecepcionMercanciaLineaId
        WHERE h.Estado='CONTABILIZADA' AND d.Estado<>'CONTABILIZADA' AND a.ManejaSerial=0
    ) THROW 51895,'La línea contiene seriales pero el artículo no está configurado para manejar serial.',1;

    DECLARE @EmpresaId bigint,@RecepcionUnidadId bigint,@ArticuloId bigint,@LoteId bigint,@BodegaId bigint,@UbicacionId bigint,@UnidadId bigint,
        @Serial nvarchar(120),@Motor nvarchar(120),@Chasis nvarchar(120),@Vin nvarchar(120),@CantidadIds int;
    DECLARE @Identificadores TABLE(Tipo varchar(20) PRIMARY KEY,Valor nvarchar(120));
    DECLARE unidades CURSOR LOCAL FAST_FORWARD FOR
        SELECT u.EmpresaId,u.RecepcionMercanciaUnidadId,l.ArticuloId,l.LoteId,COALESCE(l.BodegaId,h.BodegaId),l.UbicacionId,u.Serial,u.Motor,u.Chasis,u.Vin
        FROM inserted h
        JOIN deleted d ON d.EmpresaId=h.EmpresaId AND d.RecepcionMercanciaId=h.RecepcionMercanciaId
        JOIN inv.RecepcionMercanciaLinea l ON l.EmpresaId=h.EmpresaId AND l.RecepcionMercanciaId=h.RecepcionMercanciaId
        JOIN inv.Articulo a ON a.EmpresaId=l.EmpresaId AND a.ArticuloId=l.ArticuloId AND a.ManejaSerial=1
        JOIN inv.RecepcionMercanciaUnidad u ON u.EmpresaId=l.EmpresaId AND u.RecepcionMercanciaLineaId=l.RecepcionMercanciaLineaId
        WHERE h.Estado='CONTABILIZADA' AND d.Estado<>'CONTABILIZADA' AND u.UnidadSerializadaId IS NULL
        ORDER BY l.ArticuloId,u.RecepcionMercanciaUnidadId;
    OPEN unidades;
    FETCH NEXT FROM unidades INTO @EmpresaId,@RecepcionUnidadId,@ArticuloId,@LoteId,@BodegaId,@UbicacionId,@Serial,@Motor,@Chasis,@Vin;
    WHILE @@FETCH_STATUS=0
    BEGIN
        DELETE FROM @Identificadores;
        INSERT @Identificadores SELECT Tipo,Valor FROM
            (VALUES('SERIAL',@Serial),('MOTOR',@Motor),('CHASIS',@Chasis),('VIN',@Vin)) x(Tipo,Valor) WHERE Valor IS NOT NULL;
        SET @UnidadId=NULL;
        SELECT @UnidadId=MIN(u.UnidadSerializadaId),@CantidadIds=COUNT(DISTINCT u.UnidadSerializadaId)
        FROM inv.UnidadIdentificador u WITH(UPDLOCK,HOLDLOCK)
        JOIN @Identificadores i ON i.Tipo=u.Tipo AND i.Valor=u.Valor
        WHERE u.EmpresaId=@EmpresaId;
        IF @CantidadIds>1 THROW 51757,'Los identificadores corresponden a unidades diferentes. Revisa el chasis y el motor.',1;
        IF @UnidadId IS NULL
        BEGIN
            INSERT inv.UnidadSerializada(EmpresaId,ArticuloId,LoteId,BodegaActualId,UbicacionActualId)
            VALUES(@EmpresaId,@ArticuloId,@LoteId,@BodegaId,@UbicacionId);
            SET @UnidadId=SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            IF NOT EXISTS(
                SELECT 1 FROM inv.UnidadSerializada s WITH(UPDLOCK,HOLDLOCK)
                CROSS APPLY(SELECT TOP(1) m.MovimientoInventarioId,m.EstadoPosterior
                    FROM inv.MovimientoInventarioUnidad m
                    WHERE m.EmpresaId=s.EmpresaId AND m.UnidadSerializadaId=s.UnidadSerializadaId
                    ORDER BY m.MovimientoInventarioUnidadId DESC) ultima
                JOIN inv.ReversionMovimientoInventario rm ON rm.EmpresaId=s.EmpresaId AND rm.MovimientoReversionId=ultima.MovimientoInventarioId
                JOIN inv.MovimientoInventario original ON original.EmpresaId=rm.EmpresaId AND original.MovimientoInventarioId=rm.MovimientoOriginalId
                    AND original.TipoDocumentoOrigen='RECEPCION_MERCANCIA'
                JOIN inv.ReversionEntradaMercancia re ON re.EmpresaId=original.EmpresaId AND re.RecepcionMercanciaId=original.DocumentoOrigenId
                JOIN inv.RecepcionMercancia recibida ON recibida.EmpresaId=re.EmpresaId AND recibida.RecepcionMercanciaId=re.RecepcionMercanciaId
                WHERE s.EmpresaId=@EmpresaId AND s.UnidadSerializadaId=@UnidadId AND s.ArticuloId=@ArticuloId
                    AND s.Estado='BAJA' AND s.BodegaActualId IS NULL AND ultima.EstadoPosterior='BAJA' AND recibida.Estado='REVERTIDA'
            ) THROW 51758,'El chasis o serial ya existe y no procede de una entrada completamente revertida.',1;
            IF EXISTS(
                SELECT 1 FROM inv.UnidadIdentificador u
                JOIN @Identificadores i ON i.Tipo=u.Tipo AND i.Valor<>u.Valor
                WHERE u.EmpresaId=@EmpresaId AND u.UnidadSerializadaId=@UnidadId
            ) THROW 51759,'Los identificadores no coinciden con los de la unidad que se está reingresando.',1;
            UPDATE inv.UnidadSerializada SET Estado='DISPONIBLE',ArticuloId=@ArticuloId,LoteId=@LoteId,BodegaActualId=@BodegaId,UbicacionActualId=@UbicacionId
            WHERE EmpresaId=@EmpresaId AND UnidadSerializadaId=@UnidadId;
        END;
        UPDATE inv.RecepcionMercanciaUnidad SET UnidadSerializadaId=@UnidadId
        WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaUnidadId=@RecepcionUnidadId;
        INSERT inv.UnidadIdentificador(EmpresaId,UnidadSerializadaId,Tipo,Valor)
        SELECT @EmpresaId,@UnidadId,i.Tipo,i.Valor FROM @Identificadores i
        WHERE NOT EXISTS(SELECT 1 FROM inv.UnidadIdentificador u WHERE u.EmpresaId=@EmpresaId AND u.UnidadSerializadaId=@UnidadId AND u.Tipo=i.Tipo);
        FETCH NEXT FROM unidades INTO @EmpresaId,@RecepcionUnidadId,@ArticuloId,@LoteId,@BodegaId,@UbicacionId,@Serial,@Motor,@Chasis,@Vin;
    END;
    CLOSE unidades;
    DEALLOCATE unidades;
END;
GO

-- Las recepciones históricas de una unidad reingresada conservan su vínculo,
-- mientras la asignación del origen usa únicamente la recepción vigente.
DECLARE @Definition nvarchar(max)=OBJECT_DEFINITION(OBJECT_ID('inv.TR_MovimientoInventario_Origenes'));
IF CHARINDEX('recepcionVigente',@Definition)=0
BEGIN
    SET @Definition=STUFF(@Definition,1,CHARINDEX('TRIGGER',@Definition)-1,'ALTER ');
    SET @Definition=REPLACE(@Definition,'WHERE ru.EmpresaId=@EmpresaId AND ru.UnidadSerializadaId IN',N'WHERE ru.EmpresaId=@EmpresaId
        AND EXISTS(SELECT 1 FROM inv.RecepcionMercanciaLinea lineaVigente
            JOIN inv.RecepcionMercancia recepcionVigente ON recepcionVigente.EmpresaId=lineaVigente.EmpresaId
              AND recepcionVigente.RecepcionMercanciaId=lineaVigente.RecepcionMercanciaId
            WHERE lineaVigente.EmpresaId=ru.EmpresaId AND lineaVigente.RecepcionMercanciaLineaId=ru.RecepcionMercanciaLineaId
              AND recepcionVigente.Estado=''CONTABILIZADA'')
        AND ru.UnidadSerializadaId IN');
    IF CHARINDEX('recepcionVigente',@Definition)=0 THROW 51760,'No se pudo extender la trazabilidad de los seriales reingresados.',1;
    EXEC sys.sp_executesql @Definition;
END;
SET @Definition=OBJECT_DEFINITION(OBJECT_ID('inv.usp_ReversarMovimientoInventario'));
IF CHARINDEX('reversionCompletaEntrada',@Definition)=0
BEGIN
    SET @Definition=STUFF(@Definition,1,CHARINDEX('PROCEDURE',@Definition)-1,'ALTER ');
    SET @Definition=REPLACE(@Definition,'IF @TipoDocumento IN(',N'IF @TipoDocumento=''RECEPCION_MERCANCIA'' AND NOT EXISTS(
        SELECT 1 FROM inv.ReversionEntradaMercancia reversionCompletaEntrada
        JOIN inv.MovimientoInventario originalEntrada
          ON originalEntrada.EmpresaId=reversionCompletaEntrada.EmpresaId
          AND originalEntrada.DocumentoOrigenId=reversionCompletaEntrada.RecepcionMercanciaId
          AND originalEntrada.TipoDocumentoOrigen=''RECEPCION_MERCANCIA''
        WHERE reversionCompletaEntrada.EmpresaId=@EmpresaId
          AND originalEntrada.MovimientoInventarioId=@MovimientoOriginalId)
        THROW 51761,''Esta compra debe revertirse completa desde el documento guardado.'',1;
    IF @TipoDocumento IN(');
    IF CHARINDEX('reversionCompletaEntrada',@Definition)=0 THROW 51762,'No se pudo proteger la reversión completa de entradas.',1;
    EXEC sys.sp_executesql @Definition;
END;
GO

CREATE OR ALTER TRIGGER inv.TR_Recepcion_MapearMovimientoUnidades ON inv.RecepcionMercancia AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    INSERT inv.MovimientoInventarioUnidad
    (EmpresaId,MovimientoInventarioId,UnidadSerializadaId,EstadoAnterior,EstadoPosterior,BodegaAnteriorId,BodegaPosteriorId,UbicacionAnteriorId,UbicacionPosteriorId)
    SELECT h.EmpresaId,m.MovimientoInventarioId,u.UnidadSerializadaId,
        CASE WHEN ultima.EstadoPosterior='BAJA' THEN 'BAJA' ELSE NULL END,'DISPONIBLE',NULL,m.BodegaId,NULL,l.UbicacionId
    FROM inserted h
    JOIN deleted d ON d.EmpresaId=h.EmpresaId AND d.RecepcionMercanciaId=h.RecepcionMercanciaId
    JOIN inv.RecepcionMercanciaLinea l ON l.EmpresaId=h.EmpresaId AND l.RecepcionMercanciaId=h.RecepcionMercanciaId
    JOIN inv.RecepcionMercanciaUnidad u ON u.EmpresaId=l.EmpresaId AND u.RecepcionMercanciaLineaId=l.RecepcionMercanciaLineaId AND u.UnidadSerializadaId IS NOT NULL
    JOIN inv.MovimientoInventario m ON m.EmpresaId=l.EmpresaId AND m.TipoDocumentoOrigen='RECEPCION_MERCANCIA'
        AND m.DocumentoOrigenId=h.RecepcionMercanciaId AND m.DocumentoLineaOrigenId=l.RecepcionMercanciaLineaId
    OUTER APPLY(SELECT TOP(1) previo.EstadoPosterior FROM inv.MovimientoInventarioUnidad previo
        WHERE previo.EmpresaId=u.EmpresaId AND previo.UnidadSerializadaId=u.UnidadSerializadaId
        ORDER BY previo.MovimientoInventarioUnidadId DESC) ultima
    WHERE h.Estado='CONTABILIZADA' AND d.Estado<>'CONTABILIZADA'
        AND NOT EXISTS(SELECT 1 FROM inv.MovimientoInventarioUnidad x
            WHERE x.EmpresaId=m.EmpresaId AND x.MovimientoInventarioId=m.MovimientoInventarioId AND x.UnidadSerializadaId=u.UnidadSerializadaId);
END;
GO
EXEC sys.sp_settriggerorder @triggername=N'inv.TR_Recepcion_MapearMovimientoUnidades',@order=N'Last',@stmttype=N'UPDATE';
GO

CREATE OR ALTER TRIGGER inv.TR_RecepcionMercancia_Zeus ON inv.RecepcionMercancia AFTER INSERT,UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS(
        SELECT 1 FROM inserted i
        JOIN deleted d ON d.EmpresaId=i.EmpresaId AND d.RecepcionMercanciaId=i.RecepcionMercanciaId
        JOIN core.ZeusEnvio e ON e.EmpresaId=i.EmpresaId AND e.RecepcionMercanciaId=i.RecepcionMercanciaId
        WHERE d.Estado='CONTABILIZADA' AND i.Estado<>'CONTABILIZADA'
          AND e.Estado IN('PENDIENTE','ENVIANDO','INCIERTO','CONTABILIZADO')
          AND NOT(i.Estado='REVERTIDA' AND e.Estado='CONTABILIZADO' AND EXISTS(
              SELECT 1 FROM inv.ReversionEntradaMercancia r
              WHERE r.EmpresaId=i.EmpresaId AND r.RecepcionMercanciaId=i.RecepcionMercanciaId AND r.Estado='CONTABILIZADA'
          ))
    ) THROW 51705,'La entrada tiene un envío Zeus pendiente o contabilizado. Requiere conciliación y reversión coordinada.',1;
    INSERT core.ZeusEnvio(EmpresaId,RecepcionMercanciaId)
    SELECT i.EmpresaId,i.RecepcionMercanciaId
    FROM inserted i
    LEFT JOIN deleted d ON d.EmpresaId=i.EmpresaId AND d.RecepcionMercanciaId=i.RecepcionMercanciaId
    JOIN core.ZeusConfiguracion c ON c.EmpresaId=i.EmpresaId
    WHERE i.Estado='CONTABILIZADA' AND ISNULL(d.Estado,'')<>'CONTABILIZADA'
      AND NOT EXISTS(SELECT 1 FROM core.ZeusEnvio e WITH(UPDLOCK,HOLDLOCK)
          WHERE e.EmpresaId=i.EmpresaId AND e.RecepcionMercanciaId=i.RecepcionMercanciaId);
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_RevertirEntradaMercancia
    @EmpresaId bigint,@RecepcionMercanciaId bigint,@PeriodoInventarioId bigint,@FechaContable date,
    @Motivo nvarchar(500),@UsuarioId bigint=NULL,@CorrelationId uniqueidentifier=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Motivo=LTRIM(RTRIM(@Motivo));
    IF LEN(COALESCE(@Motivo,N''))<10 THROW 51740,'Escribe un motivo de reversión de al menos 10 caracteres.',1;
    IF @CorrelationId IS NULL SET @CorrelationId=NEWID();
    BEGIN TRANSACTION;

    DECLARE @DocumentoId bigint,@TerceroId bigint,@Estado varchar(15),@FechaOriginal date,@Numero nvarchar(50),
        @ReversionId bigint,@PeriodoContableId bigint,@ComprobanteOriginalId bigint,@ComprobanteReversionId bigint;
    SELECT @DocumentoId=DocumentoProveedorId,@TerceroId=TerceroId,@Estado=Estado,@FechaOriginal=FechaContable,@Numero=Numero
    FROM inv.RecepcionMercancia WITH(UPDLOCK,HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionMercanciaId;
    IF @Estado IS NULL THROW 51741,'La entrada no existe o no pertenece a la empresa.',1;

    SELECT @ReversionId=ReversionEntradaMercanciaId
    FROM inv.ReversionEntradaMercancia WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionMercanciaId;
    IF @ReversionId IS NOT NULL
    BEGIN
        COMMIT;
        SELECT @ReversionId ReversionEntradaMercanciaId,@RecepcionMercanciaId RecepcionMercanciaId,@DocumentoId DocumentoProveedorId,
            'REVERTIDA' Estado,(SELECT COUNT(*) FROM inv.MovimientoInventario m
            JOIN inv.ReversionMovimientoInventario r ON r.EmpresaId=m.EmpresaId AND r.MovimientoReversionId=m.MovimientoInventarioId
            JOIN inv.MovimientoInventario original ON original.EmpresaId=r.EmpresaId AND original.MovimientoInventarioId=r.MovimientoOriginalId
            WHERE m.EmpresaId=@EmpresaId AND original.TipoDocumentoOrigen='RECEPCION_MERCANCIA'
                AND original.DocumentoOrigenId=@RecepcionMercanciaId) Movimientos,CAST(1 AS bit) YaExistia;
        RETURN;
    END;
    IF @Estado<>'CONTABILIZADA' OR @DocumentoId IS NULL THROW 51742,'Selecciona una entrada contabilizada con su documento de compra.',1;
    IF @FechaContable IS NULL OR @FechaContable<@FechaOriginal THROW 51743,'La fecha de reversión debe ser igual o posterior a la entrada.',1;
    IF NOT EXISTS(
        SELECT 1 FROM core.PeriodoInventario WITH(HOLDLOCK)
        WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoInventarioId
            AND Estado IN('ABIERTO','REABIERTO') AND @FechaContable BETWEEN FechaInicio AND FechaFin
    ) THROW 51744,'Escoge un periodo abierto que corresponda a la fecha de reversión.',1;

    DECLARE @EstadoDocumento varchar(15),@NumeroFactura nvarchar(50),@TipoDocumento varchar(20),@ValorDocumento decimal(20,4);
    SELECT @EstadoDocumento=Estado,@NumeroFactura=NumeroDocumento,@TipoDocumento=TipoDocumento,@ValorDocumento=TotalPagar FROM comp.DocumentoProveedor WITH(UPDLOCK,HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoId;
    IF @EstadoDocumento<>'CONTABILIZADO' THROW 51745,'El documento de compra debe estar completamente contabilizado.',1;
    IF EXISTS(SELECT 1 FROM comp.DocumentoProveedorLinea WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoId AND Clasificacion<>'INVENTARIO')
       OR EXISTS(SELECT 1 FROM comp.CausacionServicio WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoId)
       OR EXISTS(SELECT 1 FROM inv.RecepcionMercancia WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoId AND RecepcionMercanciaId<>@RecepcionMercanciaId)
        THROW 51746,'Esta reversión admite compras completas de inventario. El documento contiene otros procesos que requieren reversión coordinada.',1;

    DECLARE @ZeusEstado varchar(25);
    SELECT @ZeusEstado=Estado FROM core.ZeusEnvio WITH(UPDLOCK,HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionMercanciaId;
    IF @ZeusEstado IN('PENDIENTE','ENVIANDO','INCIERTO')
        THROW 51747,'Primero resuelve el envío original a Zeus antes de revertir la entrada.',1;

    DECLARE @PorPagarId bigint,@Saldo decimal(20,4),@ValorOriginal decimal(20,4),@Moneda char(3),@Vence date;
    SELECT @PorPagarId=DocumentoPorPagarId,@Saldo=SaldoPendiente,@ValorOriginal=ValorOriginal,@Moneda=Moneda,@Vence=FechaVencimiento
    FROM cxp.DocumentoPorPagar WITH(UPDLOCK,HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoId;
    IF @PorPagarId IS NULL AND @TipoDocumento IN('FACTURA','DOCUMENTO_SOPORTE') AND @ValorDocumento>0
        THROW 51748,'La factura no tiene su cuenta por pagar completa. Revisa la trazabilidad de la entrada.',1;
    IF @PorPagarId IS NOT NULL AND (
        @Saldo<=0 OR @Saldo<>@ValorOriginal OR NOT EXISTS(
            SELECT 1 FROM cxp.DocumentoPorPagar WHERE EmpresaId=@EmpresaId AND DocumentoPorPagarId=@PorPagarId AND Estado='ABIERTA'
        ) OR EXISTS(
            SELECT 1 FROM cxp.MovimientoProveedor WITH(HOLDLOCK)
            WHERE EmpresaId=@EmpresaId AND DocumentoPorPagarId=@PorPagarId
                AND NOT(TipoMovimiento='FACTURA' AND TipoDocumentoOrigen='DOCUMENTO_PROVEEDOR' AND DocumentoOrigenId=@DocumentoId)
        ) OR EXISTS(
            SELECT 1 FROM cxp.EgresoLinea l WITH(HOLDLOCK)
            JOIN cxp.Egreso e ON e.EmpresaId=l.EmpresaId AND e.EgresoId=l.EgresoId
            WHERE l.EmpresaId=@EmpresaId AND l.DocumentoPorPagarId=@PorPagarId
                AND e.ZeusEstado IN('PENDIENTE','ENVIANDO','INCIERTO','CONTABILIZADO')
        )
    ) THROW 51748,'La factura tiene pagos o aplicaciones posteriores. Reviértelos antes de corregir la entrada.',1;

    DECLARE @Lineas TABLE
    (
        MovimientoId bigint PRIMARY KEY,LineaId bigint,ArticuloId bigint,BodegaId bigint,UbicacionId bigint NULL,LoteId bigint NULL,
        Cantidad decimal(20,6),Costo decimal(20,8),Valor decimal(20,4),OrigenId bigint,ManejaSerial bit,ReversaKey uniqueidentifier DEFAULT NEWID()
    );
    INSERT @Lineas(MovimientoId,LineaId,ArticuloId,BodegaId,UbicacionId,LoteId,Cantidad,Costo,Valor,OrigenId,ManejaSerial)
    SELECT m.MovimientoInventarioId,l.RecepcionMercanciaLineaId,l.ArticuloId,m.BodegaId,m.UbicacionId,m.LoteId,
        m.CantidadEntrada,m.CostoUnitarioMovimiento,m.ValorMovimiento,o.OrigenInventarioId,a.ManejaSerial
    FROM inv.RecepcionMercanciaLinea l
    JOIN inv.Articulo a ON a.EmpresaId=l.EmpresaId AND a.ArticuloId=l.ArticuloId
    JOIN inv.MovimientoInventario m ON m.EmpresaId=l.EmpresaId AND m.IdempotencyKey=l.IdempotencyKey
        AND m.TipoDocumentoOrigen='RECEPCION_MERCANCIA' AND m.DocumentoOrigenId=l.RecepcionMercanciaId
        AND m.DocumentoLineaOrigenId=l.RecepcionMercanciaLineaId AND m.CantidadEntrada=l.CantidadBase
    JOIN inv.OrigenInventario o ON o.EmpresaId=m.EmpresaId AND o.MovimientoEntradaInicialId=m.MovimientoInventarioId
    WHERE l.EmpresaId=@EmpresaId AND l.RecepcionMercanciaId=@RecepcionMercanciaId;
    IF @@ROWCOUNT=0 OR (SELECT COUNT(*) FROM @Lineas)<>(SELECT COUNT(*) FROM inv.RecepcionMercanciaLinea WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionMercanciaId)
        THROW 51749,'La entrada no tiene la trazabilidad completa de sus cantidades y costos.',1;

    DECLARE @Bodega bigint,@Articulo bigint,@Recurso nvarchar(255),@LockResult int;
    DECLARE saldos CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT BodegaId,ArticuloId FROM @Lineas ORDER BY BodegaId,ArticuloId;
    OPEN saldos;
    FETCH NEXT FROM saldos INTO @Bodega,@Articulo;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @Recurso=CONCAT(N'INV:',@EmpresaId,N':',@Bodega,N':',@Articulo);
        EXEC @LockResult=sys.sp_getapplock @Resource=@Recurso,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=15000;
        IF @LockResult<0 THROW 51750,'No fue posible bloquear las existencias. Intenta de nuevo.',1;
        FETCH NEXT FROM saldos INTO @Bodega,@Articulo;
    END;
    CLOSE saldos;
    DEALLOCATE saldos;

    IF EXISTS(
        SELECT 1 FROM @Lineas l
        LEFT JOIN inv.SaldoOrigenBodega s WITH(UPDLOCK,HOLDLOCK)
            ON s.EmpresaId=@EmpresaId AND s.OrigenInventarioId=l.OrigenId AND s.BodegaId=l.BodegaId AND s.ArticuloId=l.ArticuloId
        WHERE COALESCE(s.CantidadDisponible,0)<>l.Cantidad OR EXISTS(
            SELECT 1 FROM inv.MovimientoOrigenInventario mo WITH(HOLDLOCK)
            WHERE mo.EmpresaId=@EmpresaId AND mo.OrigenInventarioId=l.OrigenId AND mo.CantidadSalida>0
        ) OR EXISTS(
            SELECT 1 FROM inv.MovimientoInventario nextMove WITH(HOLDLOCK)
            WHERE nextMove.EmpresaId=@EmpresaId AND nextMove.MovimientoRelacionadoId=l.MovimientoId
        ) OR EXISTS(
            SELECT 1 FROM cost.DistribucionCostoLinea dl WITH(HOLDLOCK)
            JOIN cost.AplicacionCostoAdquisicion aplicada WITH(HOLDLOCK)
              ON aplicada.EmpresaId=dl.EmpresaId AND aplicada.DistribucionCostoLineaId=dl.DistribucionCostoLineaId
            WHERE dl.EmpresaId=@EmpresaId AND dl.RecepcionMercanciaLineaId=l.LineaId
        )
    ) THROW 51751,'Esta entrada tuvo ventas, traslados, devoluciones, consumo o costos posteriores y requiere una corrección contable coordinada.',1;

    IF EXISTS(
        SELECT 1 FROM @Lineas l WHERE l.ManejaSerial=1 AND (
            l.Cantidad<>(SELECT COUNT(*) FROM inv.MovimientoInventarioUnidad m
                JOIN inv.UnidadSerializada u WITH(UPDLOCK,HOLDLOCK) ON u.EmpresaId=m.EmpresaId AND u.UnidadSerializadaId=m.UnidadSerializadaId
                WHERE m.EmpresaId=@EmpresaId AND m.MovimientoInventarioId=l.MovimientoId AND u.Estado='DISPONIBLE'
                    AND u.BodegaActualId=l.BodegaId AND u.ArticuloId=l.ArticuloId
                    AND NOT EXISTS(SELECT 1 FROM inv.MovimientoInventarioUnidad x
                        WHERE x.EmpresaId=m.EmpresaId AND x.UnidadSerializadaId=m.UnidadSerializadaId
                            AND x.MovimientoInventarioUnidadId>m.MovimientoInventarioUnidadId))
        )
    ) THROW 51752,'Una unidad serializada ya no está disponible o tiene movimientos posteriores a esta entrada.',1;

    SELECT @ComprobanteOriginalId=MIN(ComprobanteContableId)
    FROM cont.ComprobanteContable WITH(UPDLOCK,HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND (
        (TipoDocumentoOrigen='RECEPCION_MERCANCIA' AND DocumentoOrigenId=@RecepcionMercanciaId)
        OR (TipoDocumentoOrigen='DOCUMENTO_PROVEEDOR' AND DocumentoOrigenId=@DocumentoId));
    IF @ComprobanteOriginalId IS NOT NULL
    BEGIN
        IF (SELECT COUNT(*) FROM cont.ComprobanteContable
            WHERE EmpresaId=@EmpresaId AND ((TipoDocumentoOrigen='RECEPCION_MERCANCIA' AND DocumentoOrigenId=@RecepcionMercanciaId)
            OR (TipoDocumentoOrigen='DOCUMENTO_PROVEEDOR' AND DocumentoOrigenId=@DocumentoId)))<>1
            THROW 51753,'La compra tiene varios comprobantes locales y requiere revisión contable.',1;
        SELECT @PeriodoContableId=MIN(PeriodoContableId)
        FROM core.PeriodoContable WITH(HOLDLOCK)
        WHERE EmpresaId=@EmpresaId AND Estado IN('ABIERTO','REABIERTO') AND @FechaContable BETWEEN FechaInicio AND FechaFin;
        IF @PeriodoContableId IS NULL OR (SELECT COUNT(*) FROM core.PeriodoContable WHERE EmpresaId=@EmpresaId AND Estado IN('ABIERTO','REABIERTO') AND @FechaContable BETWEEN FechaInicio AND FechaFin)<>1
            THROW 51754,'Escoge una fecha con un único periodo contable abierto para reversar el comprobante local.',1;
        IF EXISTS(SELECT 1 FROM cont.ComprobanteContable WHERE EmpresaId=@EmpresaId AND ComprobanteContableId=@ComprobanteOriginalId AND Estado<>'CONTABILIZADO')
           OR NOT EXISTS(SELECT 1 FROM cont.ComprobanteContableLinea WHERE EmpresaId=@EmpresaId AND ComprobanteContableId=@ComprobanteOriginalId)
            THROW 51755,'El comprobante local no está disponible para una reversión completa.',1;
        IF EXISTS(
            SELECT 1 FROM cont.ComprobanteContable c
            CROSS APPLY(SELECT SUM(Debito) Debito,SUM(Credito) Credito FROM cont.ComprobanteContableLinea
                WHERE EmpresaId=c.EmpresaId AND ComprobanteContableId=c.ComprobanteContableId) totales
            WHERE c.EmpresaId=@EmpresaId AND c.ComprobanteContableId=@ComprobanteOriginalId
                AND (c.TotalDebito<>totales.Debito OR c.TotalCredito<>totales.Credito)
        ) THROW 51755,'El comprobante local tiene diferencias entre sus líneas y totales.',1;
    END;

    INSERT inv.ReversionEntradaMercancia(EmpresaId,RecepcionMercanciaId,DocumentoProveedorId,PeriodoInventarioId,PeriodoContableId,FechaContable,Motivo,CreadoPorUsuarioId,ComprobanteOriginalId)
    VALUES(@EmpresaId,@RecepcionMercanciaId,@DocumentoId,@PeriodoInventarioId,@PeriodoContableId,@FechaContable,@Motivo,@UsuarioId,@ComprobanteOriginalId);
    SET @ReversionId=SCOPE_IDENTITY();
    DECLARE @Movimiento bigint,@Cantidad decimal(20,6),@Valor decimal(20,4),@Key uniqueidentifier,@ReversaMovimientoId bigint;
    DECLARE movimientos CURSOR LOCAL FAST_FORWARD FOR SELECT MovimientoId,Cantidad,Valor,ReversaKey FROM @Lineas ORDER BY BodegaId,ArticuloId,MovimientoId;
    OPEN movimientos;
    FETCH NEXT FROM movimientos INTO @Movimiento,@Cantidad,@Valor,@Key;
    WHILE @@FETCH_STATUS=0
    BEGIN
        -- EXEC directo conserva el motor existente y evita INSERT EXEC anidado.
        EXEC inv.usp_ReversarMovimientoInventario @EmpresaId=@EmpresaId,@MovimientoOriginalId=@Movimiento,
            @PeriodoInventarioId=@PeriodoInventarioId,@FechaContable=@FechaContable,@Motivo=@Motivo,@IdempotencyKey=@Key,
            @UsuarioId=@UsuarioId,@CorrelationId=@CorrelationId;
        SELECT @ReversaMovimientoId=MovimientoReversionId FROM inv.ReversionMovimientoInventario WHERE EmpresaId=@EmpresaId AND IdempotencyKey=@Key;
        IF NOT EXISTS(SELECT 1 FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND MovimientoInventarioId=@ReversaMovimientoId
            AND CantidadSalida=@Cantidad AND ValorMovimiento=@Valor AND ValorTotalAnterior-ValorTotalPosterior=@Valor)
            THROW 51756,'El valor actual del inventario no permite retirar exactamente el costo de la entrada original.',1;
        FETCH NEXT FROM movimientos INTO @Movimiento,@Cantidad,@Valor,@Key;
    END;
    CLOSE movimientos;
    DEALLOCATE movimientos;

    IF @ComprobanteOriginalId IS NOT NULL
    BEGIN
        INSERT cont.ComprobanteContable(EmpresaId,IdempotencyKey,Numero,FechaContable,PeriodoContableId,TipoDocumentoOrigen,
            DocumentoOrigenId,TerceroId,Concepto,TotalDebito,TotalCredito,UsuarioId,CorrelationId)
        SELECT @EmpresaId,NEWID(),CONCAT(N'REV-ENT-',@ReversionId),@FechaContable,@PeriodoContableId,'REVERSA_ENTRADA',@ReversionId,
            TerceroId,LEFT(CONCAT(N'Reversión de ',Numero,N'. ',@Motivo),500),TotalCredito,TotalDebito,@UsuarioId,@CorrelationId
        FROM cont.ComprobanteContable WHERE EmpresaId=@EmpresaId AND ComprobanteContableId=@ComprobanteOriginalId;
        SET @ComprobanteReversionId=SCOPE_IDENTITY();
        INSERT cont.ComprobanteContableLinea(EmpresaId,ComprobanteContableId,NumeroLinea,CuentaContableId,TerceroId,Descripcion,Debito,Credito,CentroCostoCodigo,ProyectoCodigo)
        SELECT @EmpresaId,@ComprobanteReversionId,NumeroLinea,CuentaContableId,TerceroId,Descripcion,Credito,Debito,CentroCostoCodigo,ProyectoCodigo
        FROM cont.ComprobanteContableLinea WHERE EmpresaId=@EmpresaId AND ComprobanteContableId=@ComprobanteOriginalId;
        UPDATE inv.ReversionEntradaMercancia SET ComprobanteReversionId=@ComprobanteReversionId WHERE EmpresaId=@EmpresaId AND ReversionEntradaMercanciaId=@ReversionId;
    END;
    IF @PorPagarId IS NOT NULL
        INSERT cxp.MovimientoProveedor(EmpresaId,TerceroId,DocumentoPorPagarId,TipoMovimiento,FechaMovimiento,FechaVencimiento,NumeroDocumento,Moneda,Cargo,Abono,TipoDocumentoOrigen,DocumentoOrigenId)
        VALUES(@EmpresaId,@TerceroId,@PorPagarId,'REVERSO',@FechaContable,@Vence,LEFT(CONCAT(N'REV-',@NumeroFactura),50),@Moneda,0,@Saldo,'DOCUMENTO_PROVEEDOR',@DocumentoId);

    UPDATE inv.RecepcionMercancia SET Estado='REVERTIDA' WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionMercanciaId;
    UPDATE comp.DocumentoProveedor SET Estado='REVERTIDO' WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoId;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresAnteriores,ValoresPosteriores,AplicacionOrigen,CorrelationId)
    VALUES(@EmpresaId,@UsuarioId,'ENTRADA_MERCANCIA_REVERTIDA','inv.RecepcionMercancia',CONVERT(nvarchar(100),@RecepcionMercanciaId),@Numero,
        N'{"estado":"CONTABILIZADA"}',(SELECT 'REVERTIDA' estado,@ReversionId reversionEntradaMercanciaId,@Motivo motivo FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),'COMPRAS',@CorrelationId);
    COMMIT;
    SELECT @ReversionId ReversionEntradaMercanciaId,@RecepcionMercanciaId RecepcionMercanciaId,@DocumentoId DocumentoProveedorId,
        'REVERTIDA' Estado,(SELECT COUNT(*) FROM @Lineas) Movimientos,CAST(0 AS bit) YaExistia;
END;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='093_purchase_entry_reversal')
    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('093_purchase_entry_reversal',N'Reversión completa de compras de inventario, cartera, comprobantes y reingreso trazable de seriales');
COMMIT;
GO
