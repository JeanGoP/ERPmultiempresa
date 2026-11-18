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
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='095_mixed_purchase_entry_reversal')
BEGIN
    CREATE TABLE inv.ReversionEntradaComprobante
    (
        ReversionEntradaComprobanteId bigint IDENTITY(1,1) NOT NULL PRIMARY KEY,
        EmpresaId bigint NOT NULL,
        ReversionEntradaMercanciaId bigint NOT NULL,
        ComprobanteOriginalId bigint NOT NULL,
        ComprobanteReversionId bigint NULL,
        CausacionServicioId bigint NULL,
        CONSTRAINT UQ_ReversionEntradaComprobante_Empresa UNIQUE(EmpresaId,ReversionEntradaComprobanteId),
        CONSTRAINT UQ_ReversionEntradaComprobante_Original UNIQUE(EmpresaId,ComprobanteOriginalId),
        CONSTRAINT FK_ReversionEntradaComprobante_Reversion FOREIGN KEY(EmpresaId,ReversionEntradaMercanciaId)
            REFERENCES inv.ReversionEntradaMercancia(EmpresaId,ReversionEntradaMercanciaId),
        CONSTRAINT FK_ReversionEntradaComprobante_Original FOREIGN KEY(EmpresaId,ComprobanteOriginalId)
            REFERENCES cont.ComprobanteContable(EmpresaId,ComprobanteContableId),
        CONSTRAINT FK_ReversionEntradaComprobante_Inverso FOREIGN KEY(EmpresaId,ComprobanteReversionId)
            REFERENCES cont.ComprobanteContable(EmpresaId,ComprobanteContableId),
        CONSTRAINT FK_ReversionEntradaComprobante_Causacion FOREIGN KEY(EmpresaId,CausacionServicioId)
            REFERENCES comp.CausacionServicio(EmpresaId,CausacionServicioId)
    );
    CREATE INDEX IX_ReversionEntradaComprobante_Reversion ON inv.ReversionEntradaComprobante(EmpresaId,ReversionEntradaMercanciaId);
    CREATE UNIQUE INDEX UX_ReversionEntradaComprobante_Inverso ON inv.ReversionEntradaComprobante(EmpresaId,ComprobanteReversionId)
        WHERE ComprobanteReversionId IS NOT NULL;
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy
        ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.ReversionEntradaComprobante,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.ReversionEntradaComprobante AFTER INSERT,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.ReversionEntradaComprobante AFTER UPDATE;');
    INSERT inv.ReversionEntradaComprobante(EmpresaId,ReversionEntradaMercanciaId,ComprobanteOriginalId,ComprobanteReversionId)
    SELECT EmpresaId,ReversionEntradaMercanciaId,ComprobanteOriginalId,ComprobanteReversionId
    FROM inv.ReversionEntradaMercancia WHERE ComprobanteOriginalId IS NOT NULL AND ComprobanteReversionId IS NOT NULL;
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
    IF @Estado NOT IN('CONTABILIZADA','BORRADOR','VALIDADA') OR @DocumentoId IS NULL
        THROW 51742,'Selecciona una compra con su entrada o causación contabilizada.',1;
    DECLARE @InventarioContabilizado bit=CASE WHEN @Estado='CONTABILIZADA' THEN 1 ELSE 0 END;
    IF @FechaContable IS NULL OR (@InventarioContabilizado=1 AND @FechaContable<@FechaOriginal) THROW 51743,'La fecha de reversión debe ser igual o posterior a la entrada.',1;
    IF NOT EXISTS(
        SELECT 1 FROM core.PeriodoInventario WITH(HOLDLOCK)
        WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoInventarioId
            AND Estado IN('ABIERTO','REABIERTO') AND @FechaContable BETWEEN FechaInicio AND FechaFin
    ) THROW 51744,'Escoge un periodo abierto que corresponda a la fecha de reversión.',1;

    DECLARE @EstadoDocumento varchar(15),@NumeroFactura nvarchar(50),@TipoDocumento varchar(20),@ValorDocumento decimal(20,4);
    SELECT @EstadoDocumento=Estado,@NumeroFactura=NumeroDocumento,@TipoDocumento=TipoDocumento,@ValorDocumento=TotalPagar FROM comp.DocumentoProveedor WITH(UPDLOCK,HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoId;
    IF @EstadoDocumento NOT IN('CONTABILIZADO','VALIDADO')
        THROW 51745,'El documento de compra no está disponible para reversión completa.',1;
    IF EXISTS(SELECT 1 FROM comp.DocumentoProveedorLinea WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoId
        AND Clasificacion NOT IN('INVENTARIO','SERVICIO_GASTO'))
       OR EXISTS(SELECT 1 FROM inv.RecepcionMercancia WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoId
           AND RecepcionMercanciaId<>@RecepcionMercanciaId)
        THROW 51746,'La compra incluye procesos de activos o costos adicionales que requieren una corrección coordinada.',1;

    DECLARE @Causaciones TABLE(CausacionId bigint PRIMARY KEY,Estado varchar(15),ComprobanteId bigint NULL,Fecha date);
    INSERT @Causaciones
    SELECT CausacionServicioId,Estado,ComprobanteContableId,FechaContable
    FROM comp.CausacionServicio WITH(UPDLOCK,HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoId;
    IF EXISTS(SELECT 1 FROM @Causaciones WHERE Estado NOT IN('CONTABILIZADA','BORRADOR','VALIDADA'))
        THROW 51763,'Una causación de esta compra ya fue cancelada o revertida fuera de este proceso.',1;
    IF @InventarioContabilizado=0 AND NOT EXISTS(SELECT 1 FROM @Causaciones WHERE Estado='CONTABILIZADA')
        THROW 51742,'La compra debe tener inventario o servicios contabilizados para registrar una reversión.',1;
    IF EXISTS(SELECT 1 FROM @Causaciones WHERE Estado='CONTABILIZADA' AND (ComprobanteId IS NULL OR Fecha>@FechaContable))
        THROW 51764,'Revisa el comprobante de la causación y escoge una fecha igual o posterior a su contabilización.',1;
    IF EXISTS(
        SELECT 1 FROM comp.DocumentoProveedorLinea dl
        WHERE dl.EmpresaId=@EmpresaId AND dl.DocumentoProveedorId=@DocumentoId AND dl.Clasificacion='SERVICIO_GASTO'
            AND NOT EXISTS(SELECT 1 FROM comp.CausacionServicioLinea cl
                JOIN @Causaciones cs ON cs.CausacionId=cl.CausacionServicioId
                WHERE cl.EmpresaId=dl.EmpresaId AND cl.DocumentoProveedorLineaId=dl.DocumentoProveedorLineaId)
    ) THROW 51765,'Falta preparar una causación de servicios del documento de compra.',1;

    DECLARE @ZeusEstado varchar(25);
    SELECT @ZeusEstado=Estado FROM core.ZeusEnvio WITH(UPDLOCK,HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionMercanciaId;
    IF @ZeusEstado IN('PENDIENTE','ENVIANDO','INCIERTO')
        THROW 51747,'Primero resuelve el envío original a Zeus antes de revertir la entrada.',1;

    DECLARE @PorPagarId bigint,@Saldo decimal(20,4),@ValorOriginal decimal(20,4),@Moneda char(3),@Vence date;
    SELECT @PorPagarId=DocumentoPorPagarId,@Saldo=SaldoPendiente,@ValorOriginal=ValorOriginal,@Moneda=Moneda,@Vence=FechaVencimiento
    FROM cxp.DocumentoPorPagar WITH(UPDLOCK,HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoId;
    IF @PorPagarId IS NULL AND @EstadoDocumento='CONTABILIZADO' AND @TipoDocumento IN('FACTURA','DOCUMENTO_SOPORTE') AND @ValorDocumento>0
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
    IF @InventarioContabilizado=1 AND (NOT EXISTS(SELECT 1 FROM @Lineas) OR (SELECT COUNT(*) FROM @Lineas)<>(SELECT COUNT(*) FROM inv.RecepcionMercanciaLinea WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionMercanciaId))
        THROW 51749,'La entrada no tiene la trazabilidad completa de sus cantidades y costos.',1;
    IF @InventarioContabilizado=0 AND EXISTS(SELECT 1 FROM inv.MovimientoInventario
        WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='RECEPCION_MERCANCIA' AND DocumentoOrigenId=@RecepcionMercanciaId)
        THROW 51749,'La entrada pendiente tiene movimientos de inventario que requieren revisión.',1;

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

    DECLARE @Comprobantes TABLE(ComprobanteId bigint PRIMARY KEY,CausacionId bigint NULL);
    INSERT @Comprobantes
    SELECT c.ComprobanteContableId,cs.CausacionId
    FROM cont.ComprobanteContable c WITH(UPDLOCK,HOLDLOCK)
    LEFT JOIN @Causaciones cs ON c.TipoDocumentoOrigen='CAUSACION_SERVICIO'
        AND c.DocumentoOrigenId=cs.CausacionId AND cs.Estado='CONTABILIZADA'
    WHERE c.EmpresaId=@EmpresaId AND (
        (c.TipoDocumentoOrigen='RECEPCION_MERCANCIA' AND c.DocumentoOrigenId=@RecepcionMercanciaId)
        OR (c.TipoDocumentoOrigen='DOCUMENTO_PROVEEDOR' AND c.DocumentoOrigenId=@DocumentoId)
        OR cs.CausacionId IS NOT NULL);
    IF EXISTS(SELECT 1 FROM @Causaciones cs WHERE cs.Estado='CONTABILIZADA' AND NOT EXISTS(
        SELECT 1 FROM @Comprobantes cp WHERE cp.ComprobanteId=cs.ComprobanteId AND cp.CausacionId=cs.CausacionId))
        THROW 51755,'El comprobante de la causación no corresponde al servicio contabilizado.',1;
    SELECT @ComprobanteOriginalId=MIN(ComprobanteId) FROM @Comprobantes;
    IF @ComprobanteOriginalId IS NOT NULL
    BEGIN
        SELECT @PeriodoContableId=MIN(PeriodoContableId)
        FROM core.PeriodoContable WITH(HOLDLOCK)
        WHERE EmpresaId=@EmpresaId AND Estado IN('ABIERTO','REABIERTO') AND @FechaContable BETWEEN FechaInicio AND FechaFin;
        IF @PeriodoContableId IS NULL OR (SELECT COUNT(*) FROM core.PeriodoContable
            WHERE EmpresaId=@EmpresaId AND Estado IN('ABIERTO','REABIERTO') AND @FechaContable BETWEEN FechaInicio AND FechaFin)<>1
            THROW 51754,'Escoge una fecha con un único periodo contable abierto para reversar los comprobantes locales.',1;
        IF EXISTS(
            SELECT 1 FROM @Comprobantes cp
            JOIN cont.ComprobanteContable c ON c.EmpresaId=@EmpresaId AND c.ComprobanteContableId=cp.ComprobanteId
            OUTER APPLY(SELECT SUM(Debito) Debito,SUM(Credito) Credito FROM cont.ComprobanteContableLinea
                WHERE EmpresaId=c.EmpresaId AND ComprobanteContableId=c.ComprobanteContableId) totales
            WHERE c.Estado<>'CONTABILIZADO' OR c.FechaContable>@FechaContable OR totales.Debito IS NULL
                OR c.TotalDebito<>totales.Debito OR c.TotalCredito<>totales.Credito)
            THROW 51755,'Un comprobante local tiene fechas, estado o totales que impiden una reversión completa.',1;
        IF EXISTS(SELECT 1 FROM inv.ReversionEntradaComprobante anterior
            JOIN @Comprobantes cp ON cp.ComprobanteId=anterior.ComprobanteOriginalId
            WHERE anterior.EmpresaId=@EmpresaId)
            THROW 51766,'Un comprobante de la compra ya tiene una reversión registrada.',1;
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

    DECLARE @ComprobanteId bigint,@CausacionId bigint,@MapaId bigint;
    DECLARE comprobantes CURSOR LOCAL FAST_FORWARD FOR SELECT ComprobanteId,CausacionId FROM @Comprobantes ORDER BY ComprobanteId;
    OPEN comprobantes;
    FETCH NEXT FROM comprobantes INTO @ComprobanteId,@CausacionId;
    WHILE @@FETCH_STATUS=0
    BEGIN
        INSERT inv.ReversionEntradaComprobante(EmpresaId,ReversionEntradaMercanciaId,ComprobanteOriginalId,CausacionServicioId)
        VALUES(@EmpresaId,@ReversionId,@ComprobanteId,@CausacionId);
        SET @MapaId=SCOPE_IDENTITY();
        INSERT cont.ComprobanteContable(EmpresaId,IdempotencyKey,Numero,FechaContable,PeriodoContableId,TipoDocumentoOrigen,
            DocumentoOrigenId,TerceroId,Concepto,TotalDebito,TotalCredito,UsuarioId,CorrelationId)
        SELECT @EmpresaId,NEWID(),CONCAT(N'REV-ENT-',@ReversionId,N'-',@MapaId),@FechaContable,@PeriodoContableId,
            'REVERSA_ENTRADA_COMPROBANTE',@MapaId,TerceroId,LEFT(CONCAT(N'Reversión de ',Numero,N'. ',@Motivo),500),
            TotalCredito,TotalDebito,@UsuarioId,@CorrelationId
        FROM cont.ComprobanteContable WHERE EmpresaId=@EmpresaId AND ComprobanteContableId=@ComprobanteId;
        SET @ComprobanteReversionId=SCOPE_IDENTITY();
        INSERT cont.ComprobanteContableLinea(EmpresaId,ComprobanteContableId,NumeroLinea,CuentaContableId,TerceroId,Descripcion,Debito,Credito,CentroCostoCodigo,ProyectoCodigo)
        SELECT @EmpresaId,@ComprobanteReversionId,NumeroLinea,CuentaContableId,TerceroId,Descripcion,Credito,Debito,CentroCostoCodigo,ProyectoCodigo
        FROM cont.ComprobanteContableLinea WHERE EmpresaId=@EmpresaId AND ComprobanteContableId=@ComprobanteId;
        UPDATE inv.ReversionEntradaComprobante SET ComprobanteReversionId=@ComprobanteReversionId
        WHERE EmpresaId=@EmpresaId AND ReversionEntradaComprobanteId=@MapaId;
        IF @ComprobanteId=@ComprobanteOriginalId
            UPDATE inv.ReversionEntradaMercancia SET ComprobanteReversionId=@ComprobanteReversionId
            WHERE EmpresaId=@EmpresaId AND ReversionEntradaMercanciaId=@ReversionId;
        FETCH NEXT FROM comprobantes INTO @ComprobanteId,@CausacionId;
    END;
    CLOSE comprobantes;
    DEALLOCATE comprobantes;
    UPDATE cs SET Estado=CASE WHEN anterior.Estado='CONTABILIZADA' THEN 'REVERTIDA' ELSE 'CANCELADA' END
    FROM comp.CausacionServicio cs JOIN @Causaciones anterior ON anterior.CausacionId=cs.CausacionServicioId
    WHERE cs.EmpresaId=@EmpresaId;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresAnteriores,ValoresPosteriores,AplicacionOrigen,CorrelationId)
    SELECT @EmpresaId,@UsuarioId,'CAUSACION_COMPRA_REVERTIDA','comp.CausacionServicio',CONVERT(nvarchar(100),cs.CausacionServicioId),cs.Numero,
        (SELECT anterior.Estado estado FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
        (SELECT cs.Estado estado,@ReversionId reversionEntradaMercanciaId,@Motivo motivo FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),'COMPRAS',@CorrelationId
    FROM comp.CausacionServicio cs JOIN @Causaciones anterior ON anterior.CausacionId=cs.CausacionServicioId
    WHERE cs.EmpresaId=@EmpresaId;
    IF @PorPagarId IS NOT NULL
        INSERT cxp.MovimientoProveedor(EmpresaId,TerceroId,DocumentoPorPagarId,TipoMovimiento,FechaMovimiento,FechaVencimiento,NumeroDocumento,Moneda,Cargo,Abono,TipoDocumentoOrigen,DocumentoOrigenId)
        VALUES(@EmpresaId,@TerceroId,@PorPagarId,'REVERSO',@FechaContable,@Vence,LEFT(CONCAT(N'REV-',@NumeroFactura),50),@Moneda,0,@Saldo,'DOCUMENTO_PROVEEDOR',@DocumentoId);

    UPDATE inv.RecepcionMercancia SET Estado=CASE WHEN @InventarioContabilizado=1 THEN 'REVERTIDA' ELSE 'CANCELADA' END WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionMercanciaId;
    UPDATE comp.DocumentoProveedor SET Estado='REVERTIDO' WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoId;
    IF @PorPagarId IS NOT NULL
        UPDATE cxp.DocumentoPorPagar SET SaldoPendiente=0,Estado='ANULADA',ActualizadoEnUtc=SYSUTCDATETIME()
        WHERE EmpresaId=@EmpresaId AND DocumentoPorPagarId=@PorPagarId;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresAnteriores,ValoresPosteriores,AplicacionOrigen,CorrelationId)
    VALUES(@EmpresaId,@UsuarioId,'ENTRADA_MERCANCIA_REVERTIDA','inv.RecepcionMercancia',CONVERT(nvarchar(100),@RecepcionMercanciaId),@Numero,
        (SELECT @Estado estado FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
        (SELECT CASE WHEN @InventarioContabilizado=1 THEN 'REVERTIDA' ELSE 'CANCELADA' END estado,
            @ReversionId reversionEntradaMercanciaId,@Motivo motivo FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),'COMPRAS',@CorrelationId);
    COMMIT;
    SELECT @ReversionId ReversionEntradaMercanciaId,@RecepcionMercanciaId RecepcionMercanciaId,@DocumentoId DocumentoProveedorId,
        'REVERTIDA' Estado,(SELECT COUNT(*) FROM @Lineas) Movimientos,CAST(0 AS bit) YaExistia;
END;
GO

CREATE OR ALTER VIEW cont.vw_AsientoNexo AS
WITH ComprasZeusCompletas AS (
    SELECT reversa.EmpresaId,reversa.ReversionEntradaMercanciaId
    FROM inv.ReversionEntradaMercancia reversa
    JOIN core.ZeusEnvio envio ON envio.EmpresaId=reversa.EmpresaId AND envio.RecepcionMercanciaId=reversa.RecepcionMercanciaId
    JOIN comp.DocumentoProveedor factura ON factura.EmpresaId=reversa.EmpresaId AND factura.DocumentoProveedorId=reversa.DocumentoProveedorId
    WHERE envio.Estado='CONTABILIZADO' AND envio.Snapshot IS NOT NULL
        AND TRY_CONVERT(decimal(20,4),JSON_VALUE(envio.Snapshot,'$.Origen.Total'))=factura.TotalPagar
), Documentos AS (
    SELECT e.EmpresaId,CAST('ENTRADA' AS varchar(30)) Tipo,CONVERT(bigint,r.RecepcionMercanciaId) OrigenId,
        r.FechaContable Fecha,CONVERT(varchar(2),e.Fuente) Fuente,CONVERT(varchar(30),e.Documento) Documento,
        r.TerceroId,d.NumeroDocumento Referencia,e.Snapshot
    FROM core.ZeusEnvio e JOIN inv.RecepcionMercancia r ON r.EmpresaId=e.EmpresaId AND r.RecepcionMercanciaId=e.RecepcionMercanciaId
    LEFT JOIN comp.DocumentoProveedor d ON d.EmpresaId=r.EmpresaId AND d.DocumentoProveedorId=r.DocumentoProveedorId
    WHERE e.Estado='CONTABILIZADO' AND e.Snapshot IS NOT NULL
        AND NOT EXISTS (
            SELECT 1 FROM inv.ReversionEntradaMercancia reversa
            WHERE reversa.EmpresaId=r.EmpresaId AND reversa.RecepcionMercanciaId=r.RecepcionMercanciaId
                AND EXISTS(SELECT 1 FROM inv.ReversionEntradaComprobante cp
                    WHERE cp.EmpresaId=reversa.EmpresaId AND cp.ReversionEntradaMercanciaId=reversa.ReversionEntradaMercanciaId
                        AND cp.ComprobanteReversionId IS NOT NULL AND cp.CausacionServicioId IS NULL)
                AND NOT EXISTS(SELECT 1 FROM ComprasZeusCompletas completa
                    WHERE completa.EmpresaId=reversa.EmpresaId AND completa.ReversionEntradaMercanciaId=reversa.ReversionEntradaMercanciaId)
        )
    UNION ALL
    SELECT reversa.EmpresaId,'REVERSO_ENTRADA',CONVERT(bigint,reversa.ReversionEntradaMercanciaId),reversa.FechaContable,
        reversa.ZeusFuente,reversa.ZeusDocumento,r.TerceroId,CONCAT('Reverso ',d.NumeroDocumento),reversa.ZeusSnapshot
    FROM inv.ReversionEntradaMercancia reversa
    JOIN inv.RecepcionMercancia r ON r.EmpresaId=reversa.EmpresaId AND r.RecepcionMercanciaId=reversa.RecepcionMercanciaId
    JOIN comp.DocumentoProveedor d ON d.EmpresaId=reversa.EmpresaId AND d.DocumentoProveedorId=reversa.DocumentoProveedorId
    WHERE reversa.Estado='CONTABILIZADA' AND reversa.ZeusEstado='CONTABILIZADO' AND reversa.ZeusSnapshot IS NOT NULL
        AND (EXISTS(SELECT 1 FROM ComprasZeusCompletas completa
            WHERE completa.EmpresaId=reversa.EmpresaId AND completa.ReversionEntradaMercanciaId=reversa.ReversionEntradaMercanciaId)
        OR NOT EXISTS(SELECT 1 FROM inv.ReversionEntradaComprobante cp
            WHERE cp.EmpresaId=reversa.EmpresaId AND cp.ReversionEntradaMercanciaId=reversa.ReversionEntradaMercanciaId
                AND cp.ComprobanteReversionId IS NOT NULL AND cp.CausacionServicioId IS NULL))
    UNION ALL
    SELECT e.EmpresaId,'EGRESO',CONVERT(bigint,e.EgresoId),e.FechaContable,e.ZeusFuente,e.ZeusDocumento,
        e.TerceroId,CONCAT('CE-',e.EgresoId),e.Snapshot
    FROM cxp.Egreso e WHERE e.ZeusEstado='CONTABILIZADO'
    UNION ALL
    SELECT f.EmpresaId,'FACTURA_VENTA',CONVERT(bigint,f.FacturaVentaId),f.FechaContable,f.ZeusFuente,f.ZeusDocumento,
        f.ClienteId,f.Numero,f.Snapshot
    FROM ven.FacturaVenta f WHERE f.ZeusEstado='CONTABILIZADO' AND f.Snapshot IS NOT NULL
    UNION ALL
    SELECT r.EmpresaId,'RECIBO_CAJA',CONVERT(bigint,r.ReciboCajaId),r.FechaContable,r.ZeusFuente,r.ZeusDocumento,
        r.ClienteId,CONCAT('RC-',r.ReciboCajaId),r.Snapshot
    FROM cxc.ReciboCaja r WHERE r.ZeusEstado='CONTABILIZADO' AND r.Snapshot IS NOT NULL
    UNION ALL
    SELECT r.EmpresaId,'REVERSO_RECIBO',CONVERT(bigint,r.ReciboCajaId),r.ReversionFecha,r.ReversionFuente,r.ReversionDocumento,
        r.ClienteId,CONCAT('Reverso RC-',r.ReciboCajaId),r.ReversionSnapshot
    FROM cxc.ReciboCaja r WHERE r.ReversionEstado='CONTABILIZADO' AND r.ReversionSnapshot IS NOT NULL
    UNION ALL
    SELECT n.EmpresaId,'NOTA_CARTERA',CONVERT(bigint,n.RefinanciacionCarteraId),n.FechaContable,n.ZeusFuente,n.ZeusDocumento,
        f.ClienteId,CONCAT('NC-',n.RefinanciacionCarteraId),n.Snapshot
    FROM ven.RefinanciacionCartera n JOIN ven.FacturaVenta f ON f.EmpresaId=n.EmpresaId AND f.FacturaVentaId=n.FacturaVentaId
    WHERE n.ZeusEstado='CONTABILIZADO'
), ZeusLineas AS (
    SELECT d.EmpresaId,d.Tipo,d.OrigenId,d.Fecha,d.Fuente,d.Documento,d.TerceroId,d.Referencia,
        TRY_CONVERT(int,j.[key])+1 NumeroLinea,
        CONVERT(varchar(30),JSON_VALUE(j.value,'$.Regla.Cuenta')) Cuenta,
        CONVERT(nvarchar(200),JSON_VALUE(j.value,'$.Regla.Concepto')) Descripcion,
        CONVERT(varchar(50),JSON_VALUE(j.value,'$.Regla.CentroCosto')) CentroCosto,
        CONVERT(decimal(20,4),CASE WHEN v.Valor>0 THEN v.Valor ELSE 0 END) Debito,
        CONVERT(decimal(20,4),CASE WHEN v.Valor<0 THEN -v.Valor ELSE 0 END) Credito
    FROM Documentos d CROSS APPLY OPENJSON(d.Snapshot,'$.Movimientos') j
    CROSS APPLY (SELECT TRY_CONVERT(decimal(20,4),JSON_VALUE(j.value,'$.Valor')) Valor) v
    WHERE v.Valor<>0 AND JSON_VALUE(j.value,'$.Regla.Cuenta') IS NOT NULL
)
SELECT EmpresaId,Tipo,OrigenId,Fecha,Fuente,Documento,TerceroId,Referencia,NumeroLinea,Cuenta,Descripcion,CentroCosto,Debito,Credito
FROM ZeusLineas
UNION ALL
SELECT c.EmpresaId,CONVERT(varchar(30),'COMPROBANTE_NEXO'),CONVERT(bigint,c.ComprobanteContableId),c.FechaContable,
    CONVERT(varchar(2),NULL),CONVERT(varchar(30),c.Numero),COALESCE(l.TerceroId,c.TerceroId),c.Concepto,
    l.NumeroLinea,CONVERT(varchar(30),a.Codigo),CONVERT(nvarchar(200),l.Descripcion),CONVERT(varchar(50),l.CentroCostoCodigo),l.Debito,l.Credito
FROM cont.ComprobanteContable c JOIN cont.ComprobanteContableLinea l ON l.EmpresaId=c.EmpresaId AND l.ComprobanteContableId=c.ComprobanteContableId
JOIN cont.CuentaContable a ON a.EmpresaId=l.EmpresaId AND a.CuentaContableId=l.CuentaContableId
WHERE c.Estado='CONTABILIZADO'
    AND NOT EXISTS(
        SELECT 1 FROM inv.ReversionEntradaComprobante cp
        JOIN ComprasZeusCompletas completa ON completa.EmpresaId=cp.EmpresaId
            AND completa.ReversionEntradaMercanciaId=cp.ReversionEntradaMercanciaId
        WHERE cp.EmpresaId=c.EmpresaId
            AND (cp.ComprobanteOriginalId=c.ComprobanteContableId OR cp.ComprobanteReversionId=c.ComprobanteContableId)
    );
GO
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='095_mixed_purchase_entry_reversal')
    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('095_mixed_purchase_entry_reversal',N'Reversión completa de compras mixtas con todos sus servicios y comprobantes contables');
COMMIT;
GO
