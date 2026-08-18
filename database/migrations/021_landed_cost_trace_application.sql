SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='021_landed_cost_trace_application')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
    ALTER TABLE cost.DistribucionCostoLinea ADD CONSTRAINT UQ_DistribucionCostoLinea_EmpresaId UNIQUE(EmpresaId,DistribucionCostoLineaId);
    CREATE TABLE cost.AplicacionCostoAdquisicion
    (
        AplicacionCostoAdquisicionId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        DistribucionCostoLineaId bigint NOT NULL,
        TipoDestino varchar(30) NOT NULL,
        BodegaId bigint NULL,
        CantidadAtribuida decimal(20,6) NOT NULL,
        ValorAplicado decimal(20,4) NOT NULL,
        IdempotencyKey uniqueidentifier NOT NULL CONSTRAINT DF_AplicacionCosto_Key DEFAULT NEWID(),
        MovimientoAjusteId bigint NULL,
        AplicadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_AplicacionCosto_Fecha DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_AplicacionCostoAdquisicion PRIMARY KEY CLUSTERED(AplicacionCostoAdquisicionId),
        CONSTRAINT UQ_AplicacionCostoAdquisicion_EmpresaId UNIQUE(EmpresaId,AplicacionCostoAdquisicionId),
        CONSTRAINT UQ_AplicacionCostoAdquisicion_Destino UNIQUE(EmpresaId,DistribucionCostoLineaId,TipoDestino,BodegaId),
        CONSTRAINT UQ_AplicacionCostoAdquisicion_Key UNIQUE(EmpresaId,IdempotencyKey),
        CONSTRAINT FK_AplicacionCostoAdquisicion_Linea FOREIGN KEY(EmpresaId,DistribucionCostoLineaId) REFERENCES cost.DistribucionCostoLinea(EmpresaId,DistribucionCostoLineaId),
        CONSTRAINT FK_AplicacionCostoAdquisicion_Bodega FOREIGN KEY(EmpresaId,BodegaId) REFERENCES inv.Bodega(EmpresaId,BodegaId),
        CONSTRAINT FK_AplicacionCostoAdquisicion_Movimiento FOREIGN KEY(EmpresaId,MovimientoAjusteId) REFERENCES inv.MovimientoInventario(EmpresaId,MovimientoInventarioId),
        CONSTRAINT CK_AplicacionCostoAdquisicion_Tipo CHECK(TipoDestino IN('COSTO_RECEPCION','INVENTARIO','DEVOLUCION_PROVEEDOR','RESULTADO_PERIODO')),
        CONSTRAINT CK_AplicacionCostoAdquisicion_Valores CHECK(CantidadAtribuida>=0 AND ValorAplicado>=0)
    );
    CREATE INDEX IX_AplicacionCostoAdquisicion_Linea ON cost.AplicacionCostoAdquisicion(EmpresaId,DistribucionCostoLineaId) INCLUDE(TipoDestino,BodegaId,CantidadAtribuida,ValorAplicado,MovimientoAjusteId);
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cost.AplicacionCostoAdquisicion;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cost.AplicacionCostoAdquisicion AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cost.AplicacionCostoAdquisicion AFTER UPDATE;');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('021_landed_cost_trace_application',N'Aplicación de costos tardíos sobre existencias trasladadas, devoluciones y consumos');
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
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

    DECLARE @DistribucionLineaId bigint,@RecepcionLineaId bigint,@Valor decimal(20,4),@RecepcionId bigint,@RecepcionEstado varchar(15),
            @ArticuloId bigint,@CantidadOriginal decimal(20,6),@OrigenId bigint,@CantidadActual decimal(20,6),@CantidadDevuelta decimal(20,6),
            @CantidadResultado decimal(20,6),@SumaCantidad decimal(20,6),@DiferenciaValor decimal(20,4),@AplicacionId bigint,
            @TipoDestino varchar(30),@BodegaId bigint,@CantidadDestino decimal(20,6),@ValorDestino decimal(20,4),@Key uniqueidentifier,
            @MovimientoRecepcionId bigint,@MovimientoAjusteId bigint;
    DECLARE @R TABLE(MovimientoInventarioId bigint,ExistenciaPosterior decimal(20,6),CostoPromedioPosterior decimal(20,8),ValorTotalPosterior decimal(20,4),YaExistia bit);
    DECLARE lineas CURSOR LOCAL FAST_FORWARD FOR
        SELECT dl.DistribucionCostoLineaId,dl.RecepcionMercanciaLineaId,dl.ValorAsignado,r.RecepcionMercanciaId,h.Estado,r.ArticuloId,r.CantidadBase
        FROM cost.DistribucionCostoLinea dl JOIN inv.RecepcionMercanciaLinea r ON r.EmpresaId=dl.EmpresaId AND r.RecepcionMercanciaLineaId=dl.RecepcionMercanciaLineaId
        JOIN inv.RecepcionMercancia h ON h.EmpresaId=r.EmpresaId AND h.RecepcionMercanciaId=r.RecepcionMercanciaId
        WHERE dl.EmpresaId=@EmpresaId AND dl.DistribucionCostoId=@DistribucionCostoId ORDER BY r.ArticuloId,dl.RecepcionMercanciaLineaId;
    OPEN lineas; FETCH NEXT FROM lineas INTO @DistribucionLineaId,@RecepcionLineaId,@Valor,@RecepcionId,@RecepcionEstado,@ArticuloId,@CantidadOriginal;
    WHILE @@FETCH_STATUS=0
    BEGIN
        IF @RecepcionEstado NOT IN('BORRADOR','VALIDADA','CONTABILIZADA') THROW 51853,'Una recepción objetivo no admite costos adicionales en su estado actual.',1;
        UPDATE inv.RecepcionMercanciaLinea SET CostoAdicionalAsignado=CostoAdicionalAsignado+@Valor,CostoTotalCapitalizable=CostoTotalCapitalizable+@Valor
        WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaLineaId=@RecepcionLineaId;

        DECLARE @Destinos TABLE(Orden int IDENTITY(1,1),TipoDestino varchar(30),BodegaId bigint NULL,Cantidad decimal(20,6),Valor decimal(20,4));
        IF @RecepcionEstado<>'CONTABILIZADA'
            INSERT @Destinos(TipoDestino,BodegaId,Cantidad,Valor) VALUES('COSTO_RECEPCION',NULL,@CantidadOriginal,@Valor);
        ELSE
        BEGIN
            IF @PeriodoInventarioId IS NULL OR @FechaContable IS NULL THROW 51854,'La aplicación posterior requiere periodo y fecha contable vigentes.',1;
            SELECT @OrigenId=OrigenInventarioId FROM inv.OrigenInventario WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaLineaId=@RecepcionLineaId;
            IF @OrigenId IS NULL THROW 51855,'No se encontró la trazabilidad de origen de la recepción.',1;
            INSERT @Destinos(TipoDestino,BodegaId,Cantidad,Valor)
            SELECT 'INVENTARIO',BodegaId,CantidadDisponible,0 FROM inv.SaldoOrigenBodega
            WHERE EmpresaId=@EmpresaId AND OrigenInventarioId=@OrigenId AND CantidadDisponible>0 ORDER BY BodegaId;
            SET @CantidadActual=COALESCE((SELECT SUM(Cantidad) FROM @Destinos WHERE TipoDestino='INVENTARIO'),0);
            SELECT @CantidadDevuelta=COALESCE(SUM(mo.CantidadSalida),0)
            FROM inv.MovimientoOrigenInventario mo JOIN inv.MovimientoInventario m ON m.EmpresaId=mo.EmpresaId AND m.MovimientoInventarioId=mo.MovimientoInventarioId
            WHERE mo.EmpresaId=@EmpresaId AND mo.OrigenInventarioId=@OrigenId AND mo.CantidadSalida>0 AND m.TipoDocumentoOrigen='DEVOLUCION_PROVEEDOR';
            SET @CantidadResultado=@CantidadOriginal-@CantidadActual-@CantidadDevuelta;
            IF @CantidadResultado<-0.000001 THROW 51856,'La trazabilidad de origen excede la cantidad original recibida.',1;
            IF @CantidadDevuelta>0 INSERT @Destinos(TipoDestino,BodegaId,Cantidad,Valor) VALUES('DEVOLUCION_PROVEEDOR',NULL,@CantidadDevuelta,0);
            IF @CantidadResultado>0 INSERT @Destinos(TipoDestino,BodegaId,Cantidad,Valor) VALUES('RESULTADO_PERIODO',NULL,@CantidadResultado,0);
            SET @SumaCantidad=COALESCE((SELECT SUM(Cantidad) FROM @Destinos),0);
            IF ABS(@SumaCantidad-@CantidadOriginal)>0.000001 THROW 51857,'Las cantidades de destino no reconcilian con la recepción original.',1;
            UPDATE @Destinos SET Valor=CAST(ROUND(@Valor*Cantidad/@CantidadOriginal,4) AS decimal(20,4));
            SET @DiferenciaValor=@Valor-COALESCE((SELECT SUM(Valor) FROM @Destinos),0);
            IF @DiferenciaValor<>0 UPDATE @Destinos SET Valor=Valor+@DiferenciaValor WHERE Orden=(SELECT MAX(Orden) FROM @Destinos);
        END;

        INSERT cost.AplicacionCostoAdquisicion(EmpresaId,DistribucionCostoLineaId,TipoDestino,BodegaId,CantidadAtribuida,ValorAplicado)
        SELECT @EmpresaId,@DistribucionLineaId,TipoDestino,BodegaId,Cantidad,Valor FROM @Destinos;

        SELECT @MovimientoRecepcionId=MovimientoInventarioId FROM inv.MovimientoInventario
        WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='RECEPCION_MERCANCIA' AND DocumentoLineaOrigenId=@RecepcionLineaId;
        DECLARE destinos CURSOR LOCAL FAST_FORWARD FOR
            SELECT AplicacionCostoAdquisicionId,TipoDestino,BodegaId,CantidadAtribuida,ValorAplicado,IdempotencyKey
            FROM cost.AplicacionCostoAdquisicion WHERE EmpresaId=@EmpresaId AND DistribucionCostoLineaId=@DistribucionLineaId ORDER BY AplicacionCostoAdquisicionId;
        OPEN destinos; FETCH NEXT FROM destinos INTO @AplicacionId,@TipoDestino,@BodegaId,@CantidadDestino,@ValorDestino,@Key;
        WHILE @@FETCH_STATUS=0
        BEGIN
            IF @TipoDestino='INVENTARIO' AND @ValorDestino>0
            BEGIN
                DELETE FROM @R;
                INSERT @R EXEC inv.usp_AjustarValorInventario @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoInventarioId,
                    @FechaMovimiento=@FechaContable,@FechaContable=@FechaContable,@TipoDocumentoOrigen='DISTRIBUCION_COSTO',@DocumentoOrigenId=@DistribucionCostoId,
                    @DocumentoLineaOrigenId=@AplicacionId,@NumeroDocumento=@Numero,@ValorAjuste=@ValorDestino,@IdempotencyKey=@Key,@UsuarioId=@UsuarioId,
                    @CorrelationId=@CorrelationId,@MovimientoRelacionadoId=@MovimientoRecepcionId;
                SELECT @MovimientoAjusteId=MovimientoInventarioId FROM @R;
                UPDATE cost.AplicacionCostoAdquisicion SET MovimientoAjusteId=@MovimientoAjusteId WHERE EmpresaId=@EmpresaId AND AplicacionCostoAdquisicionId=@AplicacionId;
            END
            ELSE IF @TipoDestino IN('DEVOLUCION_PROVEEDOR','RESULTADO_PERIODO') AND @ValorDestino>0
                INSERT core.OutboxEvento(EmpresaId,TipoEvento,TipoAgregado,AgregadoId,Payload)
                VALUES(@EmpresaId,N'Costos.VariacionAdquisicionReconocida',N'AplicacionCostoAdquisicion',CONVERT(nvarchar(100),@AplicacionId),
                    CONCAT(N'{"aplicacionId":',@AplicacionId,N',"tipo":"',@TipoDestino,N'","cantidad":',CONVERT(varchar(50),@CantidadDestino),N',"valor":',CONVERT(varchar(50),@ValorDestino),N',"fecha":"',CONVERT(char(10),@FechaContable,23),N'"}'));
            FETCH NEXT FROM destinos INTO @AplicacionId,@TipoDestino,@BodegaId,@CantidadDestino,@ValorDestino,@Key;
        END;
        CLOSE destinos; DEALLOCATE destinos;
        SET @OrigenId=NULL; SET @MovimientoRecepcionId=NULL; SET @MovimientoAjusteId=NULL;
        FETCH NEXT FROM lineas INTO @DistribucionLineaId,@RecepcionLineaId,@Valor,@RecepcionId,@RecepcionEstado,@ArticuloId,@CantidadOriginal;
    END;
    CLOSE lineas; DEALLOCATE lineas;
    IF (SELECT SUM(a.ValorAplicado) FROM cost.AplicacionCostoAdquisicion a JOIN cost.DistribucionCostoLinea l ON l.EmpresaId=a.EmpresaId AND l.DistribucionCostoLineaId=a.DistribucionCostoLineaId WHERE l.EmpresaId=@EmpresaId AND l.DistribucionCostoId=@DistribucionCostoId)
       <>(SELECT ValorTotal FROM cost.DistribucionCosto WHERE EmpresaId=@EmpresaId AND DistribucionCostoId=@DistribucionCostoId)
        THROW 51858,'Las aplicaciones no reconcilian exactamente con el costo distribuido.',1;
    UPDATE cost.DistribucionCosto SET Estado='APLICADA',AplicadaEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@EmpresaId AND DistribucionCostoId=@DistribucionCostoId;
    UPDATE cost.DocumentoCostoAdquisicion SET Estado='APLICADO' WHERE EmpresaId=@EmpresaId AND DocumentoCostoId=@DocumentoCostoId;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresPosteriores,AplicacionOrigen,CorrelationId)
    VALUES(@EmpresaId,@UsuarioId,'COSTO_DISTRIBUCION_APLICADA','cost.DistribucionCosto',CONVERT(nvarchar(100),@DistribucionCostoId),@Numero,N'{"estado":"APLICADA"}','COSTOS',@CorrelationId);
    COMMIT;
    SELECT @DistribucionCostoId DistribucionCostoId,CAST('APLICADA' AS varchar(20)) Estado,(SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='DISTRIBUCION_COSTO' AND DocumentoOrigenId=@DistribucionCostoId) AjustesKardex,CAST(0 AS bit) YaExistia;
END;
GO
