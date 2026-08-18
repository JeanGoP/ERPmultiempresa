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

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='010_transfer_workflow')
BEGIN
    BEGIN TRANSACTION;
    ALTER TABLE inv.Traslado ADD PeriodoSalidaId bigint NULL,FechaContableSalida date NULL,PeriodoRecepcionId bigint NULL,FechaContableRecepcion date NULL;
    ALTER TABLE inv.Traslado ADD CONSTRAINT FK_Traslado_PeriodoSalida FOREIGN KEY(EmpresaId,PeriodoSalidaId) REFERENCES core.PeriodoInventario(EmpresaId,PeriodoInventarioId);
    ALTER TABLE inv.Traslado ADD CONSTRAINT FK_Traslado_PeriodoRecepcion FOREIGN KEY(EmpresaId,PeriodoRecepcionId) REFERENCES core.PeriodoInventario(EmpresaId,PeriodoInventarioId);
    ALTER TABLE inv.TrasladoLinea ADD SalidaOrigenKey uniqueidentifier NOT NULL CONSTRAINT DF_TrasladoLinea_SalidaOrigenKey DEFAULT NEWID(),
        EntradaTransitoKey uniqueidentifier NOT NULL CONSTRAINT DF_TrasladoLinea_EntradaTransitoKey DEFAULT NEWID(),
        SalidaTransitoKey uniqueidentifier NOT NULL CONSTRAINT DF_TrasladoLinea_SalidaTransitoKey DEFAULT NEWID(),
        EntradaDestinoKey uniqueidentifier NOT NULL CONSTRAINT DF_TrasladoLinea_EntradaDestinoKey DEFAULT NEWID();
    CREATE UNIQUE INDEX UX_TrasladoLinea_SalidaOrigenKey ON inv.TrasladoLinea(EmpresaId,SalidaOrigenKey);
    CREATE UNIQUE INDEX UX_TrasladoLinea_EntradaTransitoKey ON inv.TrasladoLinea(EmpresaId,EntradaTransitoKey);
    CREATE UNIQUE INDEX UX_TrasladoLinea_SalidaTransitoKey ON inv.TrasladoLinea(EmpresaId,SalidaTransitoKey);
    CREATE UNIQUE INDEX UX_TrasladoLinea_EntradaDestinoKey ON inv.TrasladoLinea(EmpresaId,EntradaDestinoKey);
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('010_transfer_workflow',N'Despacho, tránsito y recepción atómica de traslados');
    COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_DespacharTraslado
    @EmpresaId bigint,@TrasladoId bigint,@PeriodoInventarioId bigint,@FechaContable date,
    @UsuarioId bigint=NULL,@CorrelationId uniqueidentifier=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @CorrelationId IS NULL SET @CorrelationId=NEWID();
    BEGIN TRANSACTION;
    DECLARE @Numero nvarchar(50),@Origen bigint,@Transito bigint,@Destino bigint,@FechaSalida datetime2(7),@Estado varchar(20);
    SELECT @Numero=Numero,@Origen=BodegaOrigenId,@Transito=BodegaTransitoId,@Destino=BodegaDestinoId,@FechaSalida=FechaSalida,@Estado=Estado
    FROM inv.Traslado WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND TrasladoId=@TrasladoId;
    IF @Estado IS NULL THROW 51700,'El traslado no existe o no pertenece a la empresa.',1;
    IF @Estado IN('DESPACHADO','EN_TRANSITO','RECIBIDO')
    BEGIN
        COMMIT;
        SELECT @TrasladoId TrasladoId,@Estado Estado,(SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='TRASLADO' AND DocumentoOrigenId=@TrasladoId) Movimientos,CAST(1 AS bit) YaExistia;
        RETURN;
    END;
    IF @Estado<>'BORRADOR' THROW 51701,'Solo un traslado en borrador puede despacharse.',1;
    IF NOT EXISTS(SELECT 1 FROM inv.TrasladoLinea WHERE EmpresaId=@EmpresaId AND TrasladoId=@TrasladoId) THROW 51702,'El traslado no contiene líneas.',1;
    IF @Transito IS NOT NULL AND (@Transito=@Origen OR @Transito=@Destino) THROW 51703,'La bodega de tránsito debe ser distinta de origen y destino.',1;

    DECLARE @LineaId bigint,@ArticuloId bigint,@LoteId bigint,@Cantidad decimal(20,6),@Costo decimal(20,8),
            @SalidaKey uniqueidentifier,@EntradaTransitoKey uniqueidentifier,@MovimientoSalida bigint;
    DECLARE @R TABLE(MovimientoInventarioId bigint,ExistenciaPosterior decimal(20,6),CostoPromedioPosterior decimal(20,8),ValorTotalPosterior decimal(20,4),YaExistia bit);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT TrasladoLineaId,ArticuloId,LoteId,CantidadDespachada,SalidaOrigenKey,EntradaTransitoKey
        FROM inv.TrasladoLinea WHERE EmpresaId=@EmpresaId AND TrasladoId=@TrasladoId ORDER BY ArticuloId,TrasladoLineaId;
    OPEN c; FETCH NEXT FROM c INTO @LineaId,@ArticuloId,@LoteId,@Cantidad,@SalidaKey,@EntradaTransitoKey;
    WHILE @@FETCH_STATUS=0
    BEGIN
        DELETE FROM @R;
        INSERT @R EXEC inv.usp_ContabilizarSalida @EmpresaId=@EmpresaId,@BodegaId=@Origen,@ArticuloId=@ArticuloId,@LoteId=@LoteId,
            @PeriodoInventarioId=@PeriodoInventarioId,@FechaMovimiento=@FechaSalida,@FechaContable=@FechaContable,
            @TipoMovimiento='TRASLADO_SALIDA',@ModuloOrigen='INVENTARIO',@TipoDocumentoOrigen='TRASLADO',@DocumentoOrigenId=@TrasladoId,
            @DocumentoLineaOrigenId=@LineaId,@NumeroDocumento=@Numero,@CantidadSalida=@Cantidad,@IdempotencyKey=@SalidaKey,@UsuarioId=@UsuarioId,@CorrelationId=@CorrelationId;
        SELECT @MovimientoSalida=MovimientoInventarioId FROM @R;
        SELECT @Costo=CostoUnitarioMovimiento FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND MovimientoInventarioId=@MovimientoSalida;
        UPDATE inv.TrasladoLinea SET CostoUnitarioSalida=@Costo WHERE EmpresaId=@EmpresaId AND TrasladoLineaId=@LineaId;
        IF @Transito IS NOT NULL
        BEGIN
            DELETE FROM @R;
            INSERT @R EXEC inv.usp_ContabilizarEntrada @EmpresaId=@EmpresaId,@BodegaId=@Transito,@ArticuloId=@ArticuloId,@LoteId=@LoteId,
                @PeriodoInventarioId=@PeriodoInventarioId,@FechaMovimiento=@FechaSalida,@FechaContable=@FechaContable,
                @TipoMovimiento='TRASLADO_ENTRADA_TRANSITO',@ModuloOrigen='INVENTARIO',@TipoDocumentoOrigen='TRASLADO',@DocumentoOrigenId=@TrasladoId,
                @DocumentoLineaOrigenId=@LineaId,@NumeroDocumento=@Numero,@CantidadEntrada=@Cantidad,@CostoUnitarioEntrada=@Costo,
                @IdempotencyKey=@EntradaTransitoKey,@UsuarioId=@UsuarioId,@CorrelationId=@CorrelationId,@MovimientoRelacionadoId=@MovimientoSalida;
        END;
        FETCH NEXT FROM c INTO @LineaId,@ArticuloId,@LoteId,@Cantidad,@SalidaKey,@EntradaTransitoKey;
    END;
    CLOSE c; DEALLOCATE c;
    SET @Estado=CASE WHEN @Transito IS NULL THEN 'DESPACHADO' ELSE 'EN_TRANSITO' END;
    UPDATE inv.Traslado SET Estado=@Estado,PeriodoSalidaId=@PeriodoInventarioId,FechaContableSalida=@FechaContable WHERE EmpresaId=@EmpresaId AND TrasladoId=@TrasladoId;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresPosteriores,AplicacionOrigen,CorrelationId)
    VALUES(@EmpresaId,@UsuarioId,'TRASLADO_DESPACHADO','inv.Traslado',CONVERT(nvarchar(100),@TrasladoId),@Numero,CONCAT(N'{"estado":"',@Estado,N'"}'),'INVENTARIO',@CorrelationId);
    COMMIT;
    SELECT @TrasladoId TrasladoId,@Estado Estado,(SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='TRASLADO' AND DocumentoOrigenId=@TrasladoId) Movimientos,CAST(0 AS bit) YaExistia;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_RecibirTraslado
    @EmpresaId bigint,@TrasladoId bigint,@PeriodoInventarioId bigint,@FechaContable date,
    @FechaRecepcion datetime2(7)=NULL,@UsuarioId bigint=NULL,@CorrelationId uniqueidentifier=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @CorrelationId IS NULL SET @CorrelationId=NEWID();
    IF @FechaRecepcion IS NULL SET @FechaRecepcion=SYSUTCDATETIME();
    BEGIN TRANSACTION;
    DECLARE @Numero nvarchar(50),@Origen bigint,@Transito bigint,@Destino bigint,@Estado varchar(20);
    SELECT @Numero=Numero,@Origen=BodegaOrigenId,@Transito=BodegaTransitoId,@Destino=BodegaDestinoId,@Estado=Estado
    FROM inv.Traslado WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND TrasladoId=@TrasladoId;
    IF @Estado IS NULL THROW 51710,'El traslado no existe o no pertenece a la empresa.',1;
    IF @Estado='RECIBIDO'
    BEGIN
        COMMIT;
        SELECT @TrasladoId TrasladoId,@Estado Estado,(SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='TRASLADO' AND DocumentoOrigenId=@TrasladoId) Movimientos,CAST(1 AS bit) YaExistia;
        RETURN;
    END;
    IF @Estado NOT IN('DESPACHADO','EN_TRANSITO') THROW 51711,'El traslado debe estar despachado o en tránsito para recibirse.',1;

    DECLARE @LineaId bigint,@ArticuloId bigint,@LoteId bigint,@Cantidad decimal(20,6),@Costo decimal(20,8),
            @SalidaOrigenKey uniqueidentifier,@SalidaTransitoKey uniqueidentifier,@EntradaDestinoKey uniqueidentifier,@MovimientoRelacionado bigint;
    DECLARE @R TABLE(MovimientoInventarioId bigint,ExistenciaPosterior decimal(20,6),CostoPromedioPosterior decimal(20,8),ValorTotalPosterior decimal(20,4),YaExistia bit);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT TrasladoLineaId,ArticuloId,LoteId,CantidadDespachada,CostoUnitarioSalida,SalidaOrigenKey,SalidaTransitoKey,EntradaDestinoKey
        FROM inv.TrasladoLinea WHERE EmpresaId=@EmpresaId AND TrasladoId=@TrasladoId ORDER BY ArticuloId,TrasladoLineaId;
    OPEN c; FETCH NEXT FROM c INTO @LineaId,@ArticuloId,@LoteId,@Cantidad,@Costo,@SalidaOrigenKey,@SalidaTransitoKey,@EntradaDestinoKey;
    WHILE @@FETCH_STATUS=0
    BEGIN
        IF @Transito IS NOT NULL
        BEGIN
            DELETE FROM @R;
            INSERT @R EXEC inv.usp_ContabilizarSalida @EmpresaId=@EmpresaId,@BodegaId=@Transito,@ArticuloId=@ArticuloId,@LoteId=@LoteId,
                @PeriodoInventarioId=@PeriodoInventarioId,@FechaMovimiento=@FechaRecepcion,@FechaContable=@FechaContable,
                @TipoMovimiento='TRASLADO_SALIDA_TRANSITO',@ModuloOrigen='INVENTARIO',@TipoDocumentoOrigen='TRASLADO',@DocumentoOrigenId=@TrasladoId,
                @DocumentoLineaOrigenId=@LineaId,@NumeroDocumento=@Numero,@CantidadSalida=@Cantidad,@IdempotencyKey=@SalidaTransitoKey,@UsuarioId=@UsuarioId,@CorrelationId=@CorrelationId;
            SELECT @MovimientoRelacionado=MovimientoInventarioId FROM @R;
            SELECT @Costo=CostoUnitarioMovimiento FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND MovimientoInventarioId=@MovimientoRelacionado;
        END
        ELSE
            SELECT @MovimientoRelacionado=MovimientoInventarioId FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND IdempotencyKey=@SalidaOrigenKey;

        DELETE FROM @R;
        INSERT @R EXEC inv.usp_ContabilizarEntrada @EmpresaId=@EmpresaId,@BodegaId=@Destino,@ArticuloId=@ArticuloId,@LoteId=@LoteId,
            @PeriodoInventarioId=@PeriodoInventarioId,@FechaMovimiento=@FechaRecepcion,@FechaContable=@FechaContable,
            @TipoMovimiento='TRASLADO_ENTRADA',@ModuloOrigen='INVENTARIO',@TipoDocumentoOrigen='TRASLADO',@DocumentoOrigenId=@TrasladoId,
            @DocumentoLineaOrigenId=@LineaId,@NumeroDocumento=@Numero,@CantidadEntrada=@Cantidad,@CostoUnitarioEntrada=@Costo,
            @IdempotencyKey=@EntradaDestinoKey,@UsuarioId=@UsuarioId,@CorrelationId=@CorrelationId,@MovimientoRelacionadoId=@MovimientoRelacionado;
        UPDATE inv.TrasladoLinea SET CantidadRecibida=@Cantidad WHERE EmpresaId=@EmpresaId AND TrasladoLineaId=@LineaId;
        FETCH NEXT FROM c INTO @LineaId,@ArticuloId,@LoteId,@Cantidad,@Costo,@SalidaOrigenKey,@SalidaTransitoKey,@EntradaDestinoKey;
    END;
    CLOSE c; DEALLOCATE c;
    SET @Estado='RECIBIDO';
    UPDATE inv.Traslado SET Estado=@Estado,FechaRecepcion=@FechaRecepcion,PeriodoRecepcionId=@PeriodoInventarioId,FechaContableRecepcion=@FechaContable WHERE EmpresaId=@EmpresaId AND TrasladoId=@TrasladoId;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresPosteriores,AplicacionOrigen,CorrelationId)
    VALUES(@EmpresaId,@UsuarioId,'TRASLADO_RECIBIDO','inv.Traslado',CONVERT(nvarchar(100),@TrasladoId),@Numero,N'{"estado":"RECIBIDO"}','INVENTARIO',@CorrelationId);
    COMMIT;
    SELECT @TrasladoId TrasladoId,@Estado Estado,(SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='TRASLADO' AND DocumentoOrigenId=@TrasladoId) Movimientos,CAST(0 AS bit) YaExistia;
END;
GO
