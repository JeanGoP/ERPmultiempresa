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

IF NOT EXISTS (SELECT 1 FROM core.SchemaMigration WHERE MigrationId='008_receipt_posting')
BEGIN
    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('008_receipt_posting',N'Contabilización atómica e idempotente de recepciones de mercancía');
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_ContabilizarRecepcion
    @EmpresaId bigint,
    @RecepcionMercanciaId bigint,
    @UsuarioId bigint=NULL,
    @CorrelationId uniqueidentifier=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @CorrelationId IS NULL SET @CorrelationId=NEWID();
    BEGIN TRANSACTION;

    DECLARE @Numero nvarchar(50),@DocumentoProveedorId bigint,@TerceroId bigint,@BodegaId bigint,
            @FechaRecepcion datetime2(7),@FechaContable date,@PeriodoInventarioId bigint,@Estado varchar(15);

    SELECT @Numero=Numero,@DocumentoProveedorId=DocumentoProveedorId,@TerceroId=TerceroId,
           @BodegaId=BodegaId,@FechaRecepcion=FechaRecepcion,@FechaContable=FechaContable,
           @PeriodoInventarioId=PeriodoInventarioId,@Estado=Estado
    FROM inv.RecepcionMercancia WITH(UPDLOCK,HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionMercanciaId;

    IF @Estado IS NULL THROW 51500,'La recepción no existe o no pertenece a la empresa.',1;
    IF @Estado='CONTABILIZADA'
    BEGIN
        COMMIT TRANSACTION;
        SELECT @RecepcionMercanciaId AS RecepcionMercanciaId,@Estado AS Estado,
               (SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='RECEPCION_MERCANCIA' AND DocumentoOrigenId=@RecepcionMercanciaId) AS Movimientos,
               CAST(1 AS bit) AS YaExistia;
        RETURN;
    END;
    IF @Estado NOT IN('BORRADOR','VALIDADA') THROW 51501,'La recepción no puede contabilizarse en su estado actual.',1;
    IF NOT EXISTS(SELECT 1 FROM inv.RecepcionMercanciaLinea WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionMercanciaId)
        THROW 51502,'La recepción no contiene líneas.',1;
    IF NOT EXISTS
    (
        SELECT 1 FROM core.PeriodoInventario
        WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoInventarioId
          AND Estado IN('ABIERTO','REABIERTO') AND @FechaContable BETWEEN FechaInicio AND FechaFin
    ) THROW 51503,'El periodo de inventario está cerrado o no corresponde a la fecha contable.',1;
    IF EXISTS
    (
        SELECT 1 FROM inv.RecepcionMercanciaLinea
        WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionMercanciaId
          AND (CantidadBase<=0 OR CostoTotalCapitalizable<0)
    ) THROW 51504,'Hay líneas con cantidad o costo capitalizable inválido.',1;

    DECLARE @LineaId bigint,@ArticuloId bigint,@UbicacionId bigint,@LoteId bigint,
            @CantidadBase decimal(20,6),@CostoTotal decimal(20,4),@CostoUnitario decimal(20,8),@IdempotencyKey uniqueidentifier;
    DECLARE @Resultado TABLE
    (
        MovimientoInventarioId bigint,
        ExistenciaPosterior decimal(20,6),
        CostoPromedioPosterior decimal(20,8),
        ValorTotalPosterior decimal(20,4),
        YaExistia bit
    );

    DECLARE lineas CURSOR LOCAL FAST_FORWARD FOR
        SELECT RecepcionMercanciaLineaId,ArticuloId,UbicacionId,LoteId,CantidadBase,CostoTotalCapitalizable,IdempotencyKey
        FROM inv.RecepcionMercanciaLinea
        WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionMercanciaId
        ORDER BY ArticuloId,RecepcionMercanciaLineaId;

    OPEN lineas;
    FETCH NEXT FROM lineas INTO @LineaId,@ArticuloId,@UbicacionId,@LoteId,@CantidadBase,@CostoTotal,@IdempotencyKey;
    WHILE @@FETCH_STATUS=0
    BEGIN
        DELETE FROM @Resultado;
        SET @CostoUnitario=CAST(@CostoTotal/@CantidadBase AS decimal(20,8));
        INSERT @Resultado
        EXEC inv.usp_ContabilizarEntrada
            @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@UbicacionId=@UbicacionId,@ArticuloId=@ArticuloId,@LoteId=@LoteId,
            @PeriodoInventarioId=@PeriodoInventarioId,@FechaMovimiento=@FechaRecepcion,@FechaContable=@FechaContable,
            @TipoMovimiento='COMPRA_PROVEEDOR',@ModuloOrigen='COMPRAS',@TipoDocumentoOrigen='RECEPCION_MERCANCIA',
            @DocumentoOrigenId=@RecepcionMercanciaId,@DocumentoLineaOrigenId=@LineaId,@NumeroDocumento=@Numero,@TerceroId=@TerceroId,
            @CantidadEntrada=@CantidadBase,@CostoUnitarioEntrada=@CostoUnitario,
            @IdempotencyKey=@IdempotencyKey,@UsuarioId=@UsuarioId,@CorrelationId=@CorrelationId;

        FETCH NEXT FROM lineas INTO @LineaId,@ArticuloId,@UbicacionId,@LoteId,@CantidadBase,@CostoTotal,@IdempotencyKey;
    END;
    CLOSE lineas;
    DEALLOCATE lineas;

    UPDATE inv.RecepcionMercancia
    SET Estado='CONTABILIZADA',ContabilizadoEnUtc=SYSUTCDATETIME()
    WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionMercanciaId;

    IF @DocumentoProveedorId IS NOT NULL
       AND NOT EXISTS
       (
           SELECT 1 FROM inv.RecepcionMercancia
           WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId AND Estado<>'CONTABILIZADA'
       )
       AND NOT EXISTS
       (
           SELECT 1 FROM comp.CausacionServicio
           WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId AND Estado<>'CONTABILIZADA'
       )
    BEGIN
        UPDATE comp.DocumentoProveedor SET Estado='CONTABILIZADO'
        WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId AND Estado='VALIDADO';
    END;

    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresPosteriores,AplicacionOrigen,CorrelationId)
    VALUES(@EmpresaId,@UsuarioId,'RECEPCION_CONTABILIZADA','inv.RecepcionMercancia',CONVERT(nvarchar(100),@RecepcionMercanciaId),@Numero,
           CONCAT(N'{"lineas":',(SELECT COUNT(*) FROM inv.RecepcionMercanciaLinea WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionMercanciaId),N'}'),
           'COMPRAS',@CorrelationId);

    COMMIT TRANSACTION;
    SELECT @RecepcionMercanciaId AS RecepcionMercanciaId,CAST('CONTABILIZADA' AS varchar(15)) AS Estado,
           (SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='RECEPCION_MERCANCIA' AND DocumentoOrigenId=@RecepcionMercanciaId) AS Movimientos,
           CAST(0 AS bit) AS YaExistia;
END;
GO
