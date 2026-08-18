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

CREATE OR ALTER PROCEDURE inv.usp_ContabilizarEntrada
    @EmpresaId               bigint,
    @BodegaId                bigint,
    @UbicacionId             bigint = NULL,
    @ArticuloId              bigint,
    @LoteId                  bigint = NULL,
    @PeriodoInventarioId     bigint,
    @FechaMovimiento         datetime2(7),
    @FechaContable           date,
    @TipoMovimiento          varchar(30),
    @ModuloOrigen            varchar(30),
    @TipoDocumentoOrigen     varchar(40),
    @DocumentoOrigenId       bigint,
    @DocumentoLineaOrigenId  bigint = NULL,
    @NumeroDocumento         nvarchar(50),
    @TerceroId               bigint = NULL,
    @CantidadEntrada         decimal(20,6),
    @CostoUnitarioEntrada    decimal(20,8),
    @IdempotencyKey          uniqueidentifier,
    @UsuarioId               bigint = NULL,
    @CorrelationId           uniqueidentifier = NULL,
    @MovimientoRelacionadoId bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @CantidadEntrada <= 0 THROW 51100, 'La cantidad de entrada debe ser mayor que cero.', 1;
    IF @CostoUnitarioEntrada < 0 THROW 51101, 'El costo unitario no puede ser negativo.', 1;

    DECLARE @MovimientoExistenteId bigint;
    SELECT @MovimientoExistenteId = MovimientoInventarioId
    FROM inv.MovimientoInventario
    WHERE EmpresaId = @EmpresaId AND IdempotencyKey = @IdempotencyKey;

    IF @MovimientoExistenteId IS NOT NULL
    BEGIN
        SELECT MovimientoInventarioId, ExistenciaPosterior, CostoPromedioPosterior, ValorTotalPosterior, CAST(1 AS bit) AS YaExistia
        FROM inv.MovimientoInventario
        WHERE EmpresaId = @EmpresaId AND MovimientoInventarioId = @MovimientoExistenteId;
        RETURN;
    END;

    BEGIN TRANSACTION;

    DECLARE @LockResult int;
    DECLARE @LockResource nvarchar(255) = CONCAT(N'INV:', @EmpresaId, N':', @BodegaId, N':', @ArticuloId);
    EXEC @LockResult = sys.sp_getapplock @Resource = @LockResource, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 15000;
    IF @LockResult < 0 THROW 51102, 'No fue posible obtener el bloqueo del saldo de inventario.', 1;

    IF NOT EXISTS
    (
        SELECT 1 FROM inv.Bodega
        WHERE EmpresaId = @EmpresaId AND BodegaId = @BodegaId AND Activa = 1
    ) THROW 51103, 'La bodega no pertenece a la empresa o está inactiva.', 1;

    IF NOT EXISTS
    (
        SELECT 1 FROM inv.Articulo
        WHERE EmpresaId = @EmpresaId AND ArticuloId = @ArticuloId AND ManejaInventario = 1 AND Activo = 1
    ) THROW 51104, 'El artículo no es inventariable, no pertenece a la empresa o está inactivo.', 1;

    IF NOT EXISTS
    (
        SELECT 1 FROM core.PeriodoInventario
        WHERE EmpresaId = @EmpresaId
          AND PeriodoInventarioId = @PeriodoInventarioId
          AND Estado IN ('ABIERTO','REABIERTO')
          AND @FechaContable BETWEEN FechaInicio AND FechaFin
    ) THROW 51105, 'El periodo de inventario no está abierto o no corresponde a la fecha contable.', 1;

    IF @UbicacionId IS NOT NULL AND NOT EXISTS
    (
        SELECT 1 FROM inv.Ubicacion
        WHERE EmpresaId = @EmpresaId AND BodegaId = @BodegaId AND UbicacionId = @UbicacionId AND Activa = 1
    ) THROW 51106, 'La ubicación no pertenece a la bodega o está inactiva.', 1;

    IF @LoteId IS NOT NULL AND NOT EXISTS
    (
        SELECT 1 FROM inv.Lote
        WHERE EmpresaId = @EmpresaId AND ArticuloId = @ArticuloId AND LoteId = @LoteId
    ) THROW 51107, 'El lote no pertenece al artículo.', 1;

    DECLARE @ExistenciaAnterior decimal(20,6) = 0;
    DECLARE @ValorAnterior decimal(20,4) = 0;
    DECLARE @CostoAnterior decimal(20,8) = 0;

    SELECT
        @ExistenciaAnterior = Existencia,
        @ValorAnterior = ValorTotal,
        @CostoAnterior = CostoPromedio
    FROM inv.SaldoArticuloBodega WITH (UPDLOCK, HOLDLOCK)
    WHERE EmpresaId = @EmpresaId AND BodegaId = @BodegaId AND ArticuloId = @ArticuloId;

    IF @@ROWCOUNT = 0
    BEGIN
        INSERT inv.SaldoArticuloBodega(EmpresaId, BodegaId, ArticuloId)
        VALUES (@EmpresaId, @BodegaId, @ArticuloId);
    END;

    DECLARE @ValorMovimiento decimal(20,4) = CAST(@CantidadEntrada * @CostoUnitarioEntrada AS decimal(20,4));
    DECLARE @ExistenciaPosterior decimal(20,6) = @ExistenciaAnterior + @CantidadEntrada;
    DECLARE @ValorPosterior decimal(20,4) = @ValorAnterior + @ValorMovimiento;
    DECLARE @CostoPosterior decimal(20,8) =
        CASE WHEN @ExistenciaPosterior = 0 THEN 0
             ELSE CAST(@ValorPosterior / @ExistenciaPosterior AS decimal(20,8)) END;

    INSERT inv.MovimientoInventario
    (
        EmpresaId, IdempotencyKey, BodegaId, UbicacionId, ArticuloId, LoteId,
        PeriodoInventarioId, FechaMovimiento, FechaContable, TipoMovimiento,
        ModuloOrigen, TipoDocumentoOrigen, DocumentoOrigenId, DocumentoLineaOrigenId,
        NumeroDocumento, TerceroId, CantidadEntrada, CantidadSalida,
        ExistenciaAnterior, ExistenciaPosterior, CostoUnitarioAnterior,
        CostoUnitarioMovimiento, CostoPromedioPosterior, ValorMovimiento,
        ValorTotalAnterior, ValorTotalPosterior, MovimientoRelacionadoId,
        UsuarioId, CorrelationId
    )
    VALUES
    (
        @EmpresaId, @IdempotencyKey, @BodegaId, @UbicacionId, @ArticuloId, @LoteId,
        @PeriodoInventarioId, @FechaMovimiento, @FechaContable, @TipoMovimiento,
        @ModuloOrigen, @TipoDocumentoOrigen, @DocumentoOrigenId, @DocumentoLineaOrigenId,
        @NumeroDocumento, @TerceroId, @CantidadEntrada, 0,
        @ExistenciaAnterior, @ExistenciaPosterior, @CostoAnterior,
        @CostoUnitarioEntrada, @CostoPosterior, @ValorMovimiento,
        @ValorAnterior, @ValorPosterior, @MovimientoRelacionadoId,
        @UsuarioId, @CorrelationId
    );

    DECLARE @MovimientoId bigint = SCOPE_IDENTITY();

    UPDATE inv.SaldoArticuloBodega
    SET Existencia = @ExistenciaPosterior,
        ValorTotal = @ValorPosterior,
        CostoPromedio = @CostoPosterior,
        UltimoMovimientoId = @MovimientoId,
        ActualizadoEnUtc = SYSUTCDATETIME()
    WHERE EmpresaId = @EmpresaId AND BodegaId = @BodegaId AND ArticuloId = @ArticuloId;

    IF @UbicacionId IS NOT NULL
    BEGIN
        UPDATE inv.SaldoArticuloUbicacion WITH (UPDLOCK, HOLDLOCK)
        SET Existencia = Existencia + @CantidadEntrada
        WHERE EmpresaId = @EmpresaId AND BodegaId = @BodegaId AND UbicacionId = @UbicacionId AND ArticuloId = @ArticuloId;

        IF @@ROWCOUNT = 0
            INSERT inv.SaldoArticuloUbicacion(EmpresaId, BodegaId, UbicacionId, ArticuloId, Existencia)
            VALUES (@EmpresaId, @BodegaId, @UbicacionId, @ArticuloId, @CantidadEntrada);

        IF @LoteId IS NOT NULL
        BEGIN
            UPDATE inv.SaldoArticuloLoteUbicacion WITH (UPDLOCK, HOLDLOCK)
            SET Existencia = Existencia + @CantidadEntrada
            WHERE EmpresaId = @EmpresaId AND BodegaId = @BodegaId AND UbicacionId = @UbicacionId AND ArticuloId = @ArticuloId AND LoteId = @LoteId;

            IF @@ROWCOUNT = 0
                INSERT inv.SaldoArticuloLoteUbicacion(EmpresaId, BodegaId, UbicacionId, ArticuloId, LoteId, Existencia)
                VALUES (@EmpresaId, @BodegaId, @UbicacionId, @ArticuloId, @LoteId, @CantidadEntrada);
        END;
    END;

    INSERT audit.Evento
    (
        EmpresaId, UsuarioId, Operacion, Entidad, EntidadId, DocumentoNumero,
        ValoresAnteriores, ValoresPosteriores, AplicacionOrigen, CorrelationId
    )
    VALUES
    (
        @EmpresaId, @UsuarioId, 'INVENTARIO_ENTRADA', 'inv.MovimientoInventario', CONVERT(nvarchar(100), @MovimientoId), @NumeroDocumento,
        CONCAT(N'{"existencia":', CONVERT(varchar(50), @ExistenciaAnterior), N',"valor":', CONVERT(varchar(50), @ValorAnterior), N',"costoPromedio":', CONVERT(varchar(50), @CostoAnterior), N'}'),
        CONCAT(N'{"existencia":', CONVERT(varchar(50), @ExistenciaPosterior), N',"valor":', CONVERT(varchar(50), @ValorPosterior), N',"costoPromedio":', CONVERT(varchar(50), @CostoPosterior), N'}'),
        @ModuloOrigen, @CorrelationId
    );

    COMMIT TRANSACTION;

    SELECT @MovimientoId AS MovimientoInventarioId, @ExistenciaPosterior AS ExistenciaPosterior,
           @CostoPosterior AS CostoPromedioPosterior, @ValorPosterior AS ValorTotalPosterior,
           CAST(0 AS bit) AS YaExistia;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_ContabilizarSalida
    @EmpresaId               bigint,
    @BodegaId                bigint,
    @UbicacionId             bigint = NULL,
    @ArticuloId              bigint,
    @LoteId                  bigint = NULL,
    @PeriodoInventarioId     bigint,
    @FechaMovimiento         datetime2(7),
    @FechaContable           date,
    @TipoMovimiento          varchar(30),
    @ModuloOrigen            varchar(30),
    @TipoDocumentoOrigen     varchar(40),
    @DocumentoOrigenId       bigint,
    @DocumentoLineaOrigenId  bigint = NULL,
    @NumeroDocumento         nvarchar(50),
    @TerceroId               bigint = NULL,
    @CantidadSalida          decimal(20,6),
    @IdempotencyKey          uniqueidentifier,
    @UsuarioId               bigint = NULL,
    @CorrelationId           uniqueidentifier = NULL,
    @MovimientoRelacionadoId bigint = NULL,
    @CostoUnitarioForzado    decimal(20,8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @CantidadSalida <= 0 THROW 51200, 'La cantidad de salida debe ser mayor que cero.', 1;
    IF @CostoUnitarioForzado < 0 THROW 51208, 'El costo unitario específico no puede ser negativo.', 1;
    IF @CostoUnitarioForzado IS NOT NULL AND @TipoMovimiento NOT IN ('DEVOLUCION_PROVEEDOR','DEVOLUCION_VENTA_REVERSA','REVERSA_ENTRADA','REGULARIZACION_NEGATIVO')
        THROW 51209, 'El costo específico solo puede utilizarse en devoluciones o reversas autorizadas.', 1;

    DECLARE @MovimientoExistenteId bigint;
    SELECT @MovimientoExistenteId = MovimientoInventarioId FROM inv.MovimientoInventario
    WHERE EmpresaId = @EmpresaId AND IdempotencyKey = @IdempotencyKey;
    IF @MovimientoExistenteId IS NOT NULL
    BEGIN
        SELECT MovimientoInventarioId, ExistenciaPosterior, CostoPromedioPosterior, ValorTotalPosterior, CAST(1 AS bit) AS YaExistia
        FROM inv.MovimientoInventario WHERE EmpresaId = @EmpresaId AND MovimientoInventarioId = @MovimientoExistenteId;
        RETURN;
    END;

    BEGIN TRANSACTION;
    DECLARE @LockResult int;
    DECLARE @LockResource nvarchar(255) = CONCAT(N'INV:', @EmpresaId, N':', @BodegaId, N':', @ArticuloId);
    EXEC @LockResult = sys.sp_getapplock @Resource = @LockResource, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 15000;
    IF @LockResult < 0 THROW 51201, 'No fue posible obtener el bloqueo del saldo de inventario.', 1;

    IF NOT EXISTS
    (
        SELECT 1 FROM core.PeriodoInventario
        WHERE EmpresaId = @EmpresaId AND PeriodoInventarioId = @PeriodoInventarioId
          AND Estado IN ('ABIERTO','REABIERTO') AND @FechaContable BETWEEN FechaInicio AND FechaFin
    ) THROW 51202, 'El periodo de inventario no está abierto o no corresponde a la fecha contable.', 1;

    DECLARE @ExistenciaAnterior decimal(20,6);
    DECLARE @ValorAnterior decimal(20,4);
    DECLARE @CostoAnterior decimal(20,8);
    SELECT @ExistenciaAnterior = Existencia, @ValorAnterior = ValorTotal, @CostoAnterior = CostoPromedio
    FROM inv.SaldoArticuloBodega WITH (UPDLOCK, HOLDLOCK)
    WHERE EmpresaId = @EmpresaId AND BodegaId = @BodegaId AND ArticuloId = @ArticuloId;

    IF @ExistenciaAnterior IS NULL THROW 51203, 'No existe saldo para el artículo en la bodega.', 1;

    DECLARE @PermiteNegativo bit = 0;
    SELECT @PermiteNegativo = PermiteInventarioNegativo FROM core.EmpresaConfiguracion WHERE EmpresaId = @EmpresaId;
    IF @CantidadSalida > @ExistenciaAnterior AND @PermiteNegativo = 0 THROW 51204, 'La salida supera la existencia disponible.', 1;
    IF @CantidadSalida > @ExistenciaAnterior AND @PermiteNegativo = 1 THROW 51205, 'La salida negativa requiere el flujo excepcional de regularización; no se contabiliza silenciosamente.', 1;

    IF @UbicacionId IS NOT NULL
    BEGIN
        DECLARE @ExistenciaUbicacion decimal(20,6);
        SELECT @ExistenciaUbicacion = Existencia FROM inv.SaldoArticuloUbicacion WITH (UPDLOCK, HOLDLOCK)
        WHERE EmpresaId = @EmpresaId AND BodegaId = @BodegaId AND UbicacionId = @UbicacionId AND ArticuloId = @ArticuloId;
        IF @ExistenciaUbicacion IS NULL OR @CantidadSalida > @ExistenciaUbicacion THROW 51206, 'La salida supera la existencia disponible en la ubicación.', 1;
    END;

    DECLARE @CostoMovimiento decimal(20,8) = COALESCE(@CostoUnitarioForzado,@CostoAnterior);
    DECLARE @ValorMovimiento decimal(20,4) = CAST(@CantidadSalida * @CostoMovimiento AS decimal(20,4));
    DECLARE @ExistenciaPosterior decimal(20,6) = @ExistenciaAnterior - @CantidadSalida;
    DECLARE @ValorPosterior decimal(20,4) = CASE WHEN @ExistenciaPosterior = 0 THEN 0 ELSE @ValorAnterior - @ValorMovimiento END;
    IF @ValorPosterior < 0 THROW 51210, 'El costo específico de la salida supera el valor disponible del inventario.', 1;
    DECLARE @CostoPosterior decimal(20,8) = CASE WHEN @ExistenciaPosterior = 0 THEN 0 ELSE CAST(@ValorPosterior/@ExistenciaPosterior AS decimal(20,8)) END;

    INSERT inv.MovimientoInventario
    (
        EmpresaId, IdempotencyKey, BodegaId, UbicacionId, ArticuloId, LoteId,
        PeriodoInventarioId, FechaMovimiento, FechaContable, TipoMovimiento,
        ModuloOrigen, TipoDocumentoOrigen, DocumentoOrigenId, DocumentoLineaOrigenId,
        NumeroDocumento, TerceroId, CantidadEntrada, CantidadSalida,
        ExistenciaAnterior, ExistenciaPosterior, CostoUnitarioAnterior,
        CostoUnitarioMovimiento, CostoPromedioPosterior, ValorMovimiento,
        ValorTotalAnterior, ValorTotalPosterior, MovimientoRelacionadoId,
        UsuarioId, CorrelationId
    )
    VALUES
    (
        @EmpresaId, @IdempotencyKey, @BodegaId, @UbicacionId, @ArticuloId, @LoteId,
        @PeriodoInventarioId, @FechaMovimiento, @FechaContable, @TipoMovimiento,
        @ModuloOrigen, @TipoDocumentoOrigen, @DocumentoOrigenId, @DocumentoLineaOrigenId,
        @NumeroDocumento, @TerceroId, 0, @CantidadSalida,
        @ExistenciaAnterior, @ExistenciaPosterior, @CostoAnterior,
        @CostoMovimiento, @CostoPosterior, @ValorMovimiento,
        @ValorAnterior, @ValorPosterior, @MovimientoRelacionadoId,
        @UsuarioId, @CorrelationId
    );
    DECLARE @MovimientoId bigint = SCOPE_IDENTITY();

    UPDATE inv.SaldoArticuloBodega
    SET Existencia = @ExistenciaPosterior, ValorTotal = @ValorPosterior,
        CostoPromedio = @CostoPosterior, UltimoMovimientoId = @MovimientoId,
        ActualizadoEnUtc = SYSUTCDATETIME()
    WHERE EmpresaId = @EmpresaId AND BodegaId = @BodegaId AND ArticuloId = @ArticuloId;

    IF @UbicacionId IS NOT NULL
    BEGIN
        UPDATE inv.SaldoArticuloUbicacion SET Existencia = Existencia - @CantidadSalida
        WHERE EmpresaId = @EmpresaId AND BodegaId = @BodegaId AND UbicacionId = @UbicacionId AND ArticuloId = @ArticuloId;

        IF @LoteId IS NOT NULL
        BEGIN
            UPDATE inv.SaldoArticuloLoteUbicacion SET Existencia = Existencia - @CantidadSalida
            WHERE EmpresaId = @EmpresaId AND BodegaId = @BodegaId AND UbicacionId = @UbicacionId AND ArticuloId = @ArticuloId AND LoteId = @LoteId;
            IF @@ROWCOUNT = 0 THROW 51207, 'No existe saldo del lote en la ubicación.', 1;
        END;
    END;

    INSERT audit.Evento(EmpresaId, UsuarioId, Operacion, Entidad, EntidadId, DocumentoNumero, ValoresAnteriores, ValoresPosteriores, AplicacionOrigen, CorrelationId)
    VALUES
    (
        @EmpresaId, @UsuarioId, 'INVENTARIO_SALIDA', 'inv.MovimientoInventario', CONVERT(nvarchar(100), @MovimientoId), @NumeroDocumento,
        CONCAT(N'{"existencia":', CONVERT(varchar(50), @ExistenciaAnterior), N',"valor":', CONVERT(varchar(50), @ValorAnterior), N',"costoPromedio":', CONVERT(varchar(50), @CostoAnterior), N'}'),
        CONCAT(N'{"existencia":', CONVERT(varchar(50), @ExistenciaPosterior), N',"valor":', CONVERT(varchar(50), @ValorPosterior), N',"costoPromedio":', CONVERT(varchar(50), @CostoPosterior), N'}'),
        @ModuloOrigen, @CorrelationId
    );

    COMMIT TRANSACTION;
    SELECT @MovimientoId AS MovimientoInventarioId, @ExistenciaPosterior AS ExistenciaPosterior,
           @CostoPosterior AS CostoPromedioPosterior, @ValorPosterior AS ValorTotalPosterior,
           CAST(0 AS bit) AS YaExistia;
END;
GO

IF NOT EXISTS (SELECT 1 FROM core.SchemaMigration WHERE MigrationId = '004_kardex_engine')
    INSERT core.SchemaMigration(MigrationId, Descripcion)
    VALUES ('004_kardex_engine', N'Motor transaccional e idempotente de entradas y salidas de Kardex');
GO
