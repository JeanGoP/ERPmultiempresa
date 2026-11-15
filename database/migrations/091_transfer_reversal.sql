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
IF NOT EXISTS (SELECT 1 FROM core.SchemaMigration WHERE MigrationId='091_transfer_reversal')
BEGIN
    ALTER TABLE inv.Traslado ADD TrasladoOriginalId bigint NULL;
    EXEC(N'ALTER TABLE inv.Traslado ADD CONSTRAINT FK_Traslado_Original
        FOREIGN KEY(EmpresaId,TrasladoOriginalId) REFERENCES inv.Traslado(EmpresaId,TrasladoId);
        CREATE UNIQUE INDEX UX_Traslado_Original ON inv.Traslado(EmpresaId,TrasladoOriginalId)
        WHERE TrasladoOriginalId IS NOT NULL;');
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_RevertirTraslado
    @EmpresaId bigint,@TrasladoId bigint,@PeriodoInventarioId bigint,@FechaContable date,
    @Motivo nvarchar(500),@UsuarioId bigint=NULL,@CorrelationId uniqueidentifier=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Motivo=LTRIM(RTRIM(@Motivo));
    IF LEN(COALESCE(@Motivo,N''))<10 THROW 51712,'Escribe un motivo de reversión de al menos 10 caracteres.',1;
    IF @CorrelationId IS NULL SET @CorrelationId=NEWID();

    BEGIN TRANSACTION;
    DECLARE @BodegaOriginal bigint,@BodegaDestino bigint,@Estado varchar(20),@NumeroOriginal nvarchar(50),
        @FechaOriginal date,@PadreId bigint,@ReversionId bigint;
    SELECT @BodegaOriginal=BodegaOrigenId,@BodegaDestino=BodegaDestinoId,@Estado=Estado,@NumeroOriginal=Numero,
        @FechaOriginal=CASE WHEN FechaContableSalida>FechaContableRecepcion THEN FechaContableSalida ELSE FechaContableRecepcion END,
        @PadreId=TrasladoOriginalId
    FROM inv.Traslado WITH(UPDLOCK,HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND TrasladoId=@TrasladoId;
    IF @Estado IS NULL THROW 51713,'El traslado no existe o no pertenece a la empresa.',1;
    IF @PadreId IS NOT NULL THROW 51714,'Una reversión no puede revertirse desde este formulario.',1;

    SELECT @ReversionId=TrasladoId
    FROM inv.Traslado WHERE EmpresaId=@EmpresaId AND TrasladoOriginalId=@TrasladoId;
    IF @ReversionId IS NOT NULL
    BEGIN
        COMMIT;
        SELECT @ReversionId TrasladoId,'RECIBIDO' Estado,
            (SELECT COUNT(*) FROM inv.MovimientoInventario
             WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='TRASLADO' AND DocumentoOrigenId=@ReversionId) Movimientos,
            CAST(1 AS bit) YaExistia;
        RETURN;
    END;

    IF @Estado<>'RECIBIDO' OR @FechaOriginal IS NULL THROW 51715,'Solo se puede revertir un traslado recibido en su totalidad.',1;
    IF @FechaContable IS NULL OR @FechaContable<@FechaOriginal THROW 51716,'La fecha de la reversión debe ser igual o posterior a la del traslado original.',1;
    IF NOT EXISTS(
        SELECT 1 FROM core.PeriodoInventario WITH(HOLDLOCK)
        WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoInventarioId
            AND Estado IN('ABIERTO','REABIERTO') AND @FechaContable BETWEEN FechaInicio AND FechaFin
    ) THROW 51723,'Escoge un periodo de inventario abierto que corresponda a la fecha de la reversión.',1;

    DECLARE @Lineas TABLE
    (
        NumeroLinea int PRIMARY KEY,TrasladoLineaId bigint,ArticuloId bigint,LoteId bigint NULL,
        Cantidad decimal(20,6),Costo decimal(20,8),Valor decimal(20,4),EntradaOriginalId bigint,ManejaSerial bit
    );
    INSERT @Lineas
    SELECT l.NumeroLinea,l.TrasladoLineaId,l.ArticuloId,l.LoteId,m.CantidadEntrada,m.CostoUnitarioMovimiento,
        m.ValorMovimiento,m.MovimientoInventarioId,a.ManejaSerial
    FROM inv.TrasladoLinea l
    JOIN inv.Articulo a ON a.EmpresaId=l.EmpresaId AND a.ArticuloId=l.ArticuloId
    JOIN inv.MovimientoInventario m ON m.EmpresaId=l.EmpresaId AND m.IdempotencyKey=l.EntradaDestinoKey
        AND m.BodegaId=@BodegaDestino AND m.TipoMovimiento='TRASLADO_ENTRADA'
        AND m.TipoDocumentoOrigen='TRASLADO' AND m.DocumentoOrigenId=l.TrasladoId AND m.DocumentoLineaOrigenId=l.TrasladoLineaId
    JOIN inv.MovimientoInventario s ON s.EmpresaId=l.EmpresaId AND s.IdempotencyKey=l.SalidaOrigenKey
        AND s.BodegaId=@BodegaOriginal AND s.TipoMovimiento='TRASLADO_SALIDA'
        AND s.TipoDocumentoOrigen='TRASLADO' AND s.DocumentoOrigenId=l.TrasladoId AND s.DocumentoLineaOrigenId=l.TrasladoLineaId
    WHERE l.EmpresaId=@EmpresaId AND l.TrasladoId=@TrasladoId
        AND l.CantidadRecibida=l.CantidadDespachada AND m.CantidadEntrada=l.CantidadRecibida
        AND s.CantidadSalida=l.CantidadDespachada AND s.ValorMovimiento=m.ValorMovimiento;

    IF @@ROWCOUNT=0 OR (SELECT COUNT(*) FROM @Lineas)<>
        (SELECT COUNT(*) FROM inv.TrasladoLinea WHERE EmpresaId=@EmpresaId AND TrasladoId=@TrasladoId)
        THROW 51717,'Las cantidades y costos del traslado original no permiten registrar una reversión exacta.',1;

    DECLARE @FechaMovimiento datetime2(7)=DATEADD(hour,12,CONVERT(datetime2(7),@FechaContable));
    DECLARE @Numero nvarchar(50)=CONCAT(N'REV-',@TrasladoId,N'-',RIGHT(CONVERT(varchar(36),NEWID()),12));
    INSERT inv.Traslado(EmpresaId,Numero,BodegaOrigenId,BodegaDestinoId,FechaSalida,FechaRecepcion,
        Estado,CreadoPorUsuarioId,PeriodoSalidaId,FechaContableSalida,PeriodoRecepcionId,FechaContableRecepcion,Observacion,TrasladoOriginalId)
    VALUES(@EmpresaId,@Numero,@BodegaDestino,@BodegaOriginal,@FechaMovimiento,@FechaMovimiento,
        'RECIBIDO',@UsuarioId,@PeriodoInventarioId,@FechaContable,@PeriodoInventarioId,@FechaContable,@Motivo,@TrasladoId);
    SET @ReversionId=SCOPE_IDENTITY();

    INSERT inv.TrasladoLinea(EmpresaId,TrasladoId,NumeroLinea,ArticuloId,LoteId,CantidadDespachada,CantidadRecibida,CostoUnitarioSalida)
    SELECT @EmpresaId,@ReversionId,NumeroLinea,ArticuloId,LoteId,Cantidad,Cantidad,Costo
    FROM @Lineas;

    INSERT inv.TrasladoLineaUnidad(EmpresaId,TrasladoLineaId,UnidadSerializadaId)
    SELECT @EmpresaId,r.TrasladoLineaId,u.UnidadSerializadaId
    FROM @Lineas l
    JOIN inv.TrasladoLinea r ON r.EmpresaId=@EmpresaId AND r.TrasladoId=@ReversionId AND r.NumeroLinea=l.NumeroLinea
    JOIN inv.TrasladoLineaUnidad u ON u.EmpresaId=@EmpresaId AND u.TrasladoLineaId=l.TrasladoLineaId;

    DECLARE @LineaId bigint,@ArticuloId bigint,@LoteId bigint,@EntradaOriginalId bigint,@NumeroLinea int,
        @Cantidad decimal(20,6),@Costo decimal(20,8),@Valor decimal(20,4),@ManejaSerial bit,
        @SalidaKey uniqueidentifier,@EntradaKey uniqueidentifier,@MovimientoSalida bigint,
        @LockResource nvarchar(255),@LockResult int,@OmitirOrigenAnterior sql_variant=SESSION_CONTEXT(N'OmitirOrigenAutomatico');
    DECLARE @R TABLE(MovimientoInventarioId bigint,ExistenciaPosterior decimal(20,6),CostoPromedioPosterior decimal(20,8),ValorTotalPosterior decimal(20,4),YaExistia bit);
    DECLARE @Capas TABLE(OrigenInventarioId bigint PRIMARY KEY,Cantidad decimal(20,6));

    DECLARE lineas CURSOR LOCAL FAST_FORWARD FOR
        SELECT l.NumeroLinea,l.ArticuloId,l.LoteId,l.EntradaOriginalId,l.Cantidad,l.Costo,l.Valor,l.ManejaSerial,
            r.TrasladoLineaId,r.SalidaOrigenKey,r.EntradaDestinoKey
        FROM @Lineas l
        JOIN inv.TrasladoLinea r ON r.EmpresaId=@EmpresaId AND r.TrasladoId=@ReversionId AND r.NumeroLinea=l.NumeroLinea
        ORDER BY l.ArticuloId,l.NumeroLinea;
    OPEN lineas;
    FETCH NEXT FROM lineas INTO @NumeroLinea,@ArticuloId,@LoteId,@EntradaOriginalId,@Cantidad,@Costo,@Valor,@ManejaSerial,@LineaId,@SalidaKey,@EntradaKey;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @LockResource=CONCAT(N'INV:',@EmpresaId,N':',@BodegaDestino,N':',@ArticuloId);
        EXEC @LockResult=sys.sp_getapplock @Resource=@LockResource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=15000;
        IF @LockResult<0 THROW 51718,'No fue posible bloquear la existencia en la bodega destino. Intenta de nuevo.',1;

        IF @ManejaSerial=1 AND
        (
            (SELECT COUNT(*) FROM inv.TrasladoLineaUnidad u
             JOIN inv.UnidadSerializada s WITH(UPDLOCK,HOLDLOCK)
               ON s.EmpresaId=u.EmpresaId AND s.UnidadSerializadaId=u.UnidadSerializadaId
             JOIN inv.MovimientoInventarioUnidad m
               ON m.EmpresaId=u.EmpresaId AND m.MovimientoInventarioId=@EntradaOriginalId AND m.UnidadSerializadaId=u.UnidadSerializadaId
             WHERE u.EmpresaId=@EmpresaId AND u.TrasladoLineaId=@LineaId AND s.Estado='DISPONIBLE'
                 AND s.ArticuloId=@ArticuloId AND s.BodegaActualId=@BodegaDestino AND (@LoteId IS NULL OR s.LoteId=@LoteId)
            )<>@Cantidad
        ) THROW 51719,'Una o más unidades serializadas del traslado ya no están disponibles en la bodega destino.',1;

        IF @LoteId IS NOT NULL AND COALESCE((
            SELECT SUM(CantidadEntrada-CantidadSalida) FROM inv.MovimientoInventario
            WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaDestino AND ArticuloId=@ArticuloId AND LoteId=@LoteId
        ),0)<@Cantidad THROW 51720,'El lote original ya no tiene la cantidad necesaria en la bodega destino.',1;

        DELETE FROM @Capas;
        INSERT @Capas
        SELECT OrigenInventarioId,CantidadEntrada
        FROM inv.MovimientoOrigenInventario
        WHERE EmpresaId=@EmpresaId AND MovimientoInventarioId=@EntradaOriginalId AND CantidadEntrada>0;

        IF COALESCE((SELECT SUM(Cantidad) FROM @Capas),0)<>@Cantidad OR EXISTS
        (
            SELECT 1 FROM @Capas c
            LEFT JOIN inv.SaldoOrigenBodega s WITH(UPDLOCK,HOLDLOCK)
              ON s.EmpresaId=@EmpresaId AND s.BodegaId=@BodegaDestino AND s.ArticuloId=@ArticuloId
              AND s.OrigenInventarioId=c.OrigenInventarioId
            WHERE COALESCE(s.CantidadDisponible,0)<c.Cantidad
        ) THROW 51721,'La mercancía del traslado original ya no está disponible en la bodega destino.',1;

        DELETE FROM @R;
        BEGIN TRY
            -- Las capas se descuentan abajo. El disparador de seriales sí procesa esta salida.
            EXEC sys.sp_set_session_context @key=N'OmitirOrigenAutomatico',@value=1;
            INSERT @R EXEC inv.usp_ContabilizarSalida @EmpresaId=@EmpresaId,@BodegaId=@BodegaDestino,@ArticuloId=@ArticuloId,
                @LoteId=@LoteId,@PeriodoInventarioId=@PeriodoInventarioId,@FechaMovimiento=@FechaMovimiento,@FechaContable=@FechaContable,
                @TipoMovimiento='REVERSA_ENTRADA',@ModuloOrigen='INVENTARIO',@TipoDocumentoOrigen='TRASLADO',@DocumentoOrigenId=@ReversionId,
                @DocumentoLineaOrigenId=@LineaId,@NumeroDocumento=@Numero,@CantidadSalida=@Cantidad,@IdempotencyKey=@SalidaKey,
                @UsuarioId=@UsuarioId,@CorrelationId=@CorrelationId,@MovimientoRelacionadoId=@EntradaOriginalId,@CostoUnitarioForzado=@Costo;
            EXEC sys.sp_set_session_context @key=N'OmitirOrigenAutomatico',@value=@OmitirOrigenAnterior;
        END TRY
        BEGIN CATCH
            EXEC sys.sp_set_session_context @key=N'OmitirOrigenAutomatico',@value=@OmitirOrigenAnterior;
            THROW;
        END CATCH;
        SELECT @MovimientoSalida=MovimientoInventarioId FROM @R;

        IF NOT EXISTS(
            SELECT 1 FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND MovimientoInventarioId=@MovimientoSalida
                AND ValorMovimiento=@Valor AND ValorTotalAnterior-ValorTotalPosterior=@Valor
        ) THROW 51722,'El valor actual en destino no permite retirar el costo original del traslado.',1;

        UPDATE s SET CantidadDisponible=s.CantidadDisponible-c.Cantidad,ActualizadoEnUtc=SYSUTCDATETIME()
        FROM inv.SaldoOrigenBodega s
        JOIN @Capas c ON c.OrigenInventarioId=s.OrigenInventarioId
        WHERE s.EmpresaId=@EmpresaId AND s.BodegaId=@BodegaDestino AND s.ArticuloId=@ArticuloId;

        INSERT inv.MovimientoOrigenInventario(EmpresaId,MovimientoInventarioId,OrigenInventarioId,CantidadSalida)
        SELECT @EmpresaId,@MovimientoSalida,OrigenInventarioId,Cantidad FROM @Capas;

        DELETE FROM @R;
        INSERT @R EXEC inv.usp_ContabilizarEntrada @EmpresaId=@EmpresaId,@BodegaId=@BodegaOriginal,@ArticuloId=@ArticuloId,
            @LoteId=@LoteId,@PeriodoInventarioId=@PeriodoInventarioId,@FechaMovimiento=@FechaMovimiento,@FechaContable=@FechaContable,
            @TipoMovimiento='TRASLADO_ENTRADA',@ModuloOrigen='INVENTARIO',@TipoDocumentoOrigen='TRASLADO',@DocumentoOrigenId=@ReversionId,
            @DocumentoLineaOrigenId=@LineaId,@NumeroDocumento=@Numero,@CantidadEntrada=@Cantidad,@CostoUnitarioEntrada=@Costo,
            @IdempotencyKey=@EntradaKey,@UsuarioId=@UsuarioId,@CorrelationId=@CorrelationId,@MovimientoRelacionadoId=@MovimientoSalida;

        FETCH NEXT FROM lineas INTO @NumeroLinea,@ArticuloId,@LoteId,@EntradaOriginalId,@Cantidad,@Costo,@Valor,@ManejaSerial,@LineaId,@SalidaKey,@EntradaKey;
    END;
    CLOSE lineas;
    DEALLOCATE lineas;

    UPDATE inv.Traslado SET Estado='REVERTIDO' WHERE EmpresaId=@EmpresaId AND TrasladoId=@TrasladoId;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresAnteriores,ValoresPosteriores,AplicacionOrigen,CorrelationId)
    VALUES(@EmpresaId,@UsuarioId,'TRASLADO_REVERTIDO','inv.Traslado',CONVERT(nvarchar(100),@TrasladoId),@NumeroOriginal,N'{"estado":"RECIBIDO"}',
        (SELECT 'REVERTIDO' estado,@ReversionId trasladoReversionId,@Numero numeroReversion,@Motivo motivo FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
        'INVENTARIO',@CorrelationId);
    COMMIT;

    SELECT @ReversionId TrasladoId,'RECIBIDO' Estado,
        (SELECT COUNT(*) FROM inv.MovimientoInventario
         WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='TRASLADO' AND DocumentoOrigenId=@ReversionId) Movimientos,
        CAST(0 AS bit) YaExistia;
END;
GO

IF NOT EXISTS (SELECT 1 FROM core.SchemaMigration WHERE MigrationId='091_transfer_reversal')
    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('091_transfer_reversal',N'Reversión de traslados con movimientos contrarios y trazabilidad de inventario');
COMMIT;
GO
