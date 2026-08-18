SET NOCOUNT ON;
SET XACT_ABORT ON;
EXEC sys.sp_set_session_context @key=N'BypassRls', @value=1;

BEGIN TRANSACTION;

DECLARE @Suffix varchar(12) = RIGHT(REPLACE(CONVERT(varchar(36), NEWID()), '-', ''), 12);
DECLARE @EmpresaId bigint;
DECLARE @UnidadId bigint;
DECLARE @ArticuloId bigint;
DECLARE @BodegaId bigint;
DECLARE @PeriodoId bigint;

INSERT core.Empresa(Codigo, Nit, RazonSocial)
VALUES (CONCAT('QA-', @Suffix), CONCAT('9', RIGHT(@Suffix, 9)), N'Empresa QA Kardex');
SET @EmpresaId = SCOPE_IDENTITY();

INSERT core.EmpresaConfiguracion(EmpresaId) VALUES (@EmpresaId);
INSERT inv.UnidadMedida(EmpresaId, Codigo, Nombre, Simbolo) VALUES (@EmpresaId, 'UND', N'Unidad', 'und');
SET @UnidadId = SCOPE_IDENTITY();

INSERT inv.Articulo(EmpresaId, Codigo, Descripcion, Tipo, ManejaInventario, UnidadBaseId)
VALUES (@EmpresaId, 'ART-QA', N'Artículo de prueba', 'INVENTARIO', 1, @UnidadId);
SET @ArticuloId = SCOPE_IDENTITY();

INSERT inv.Bodega(EmpresaId, Codigo, Nombre) VALUES (@EmpresaId, 'BOD-QA', N'Bodega QA');
SET @BodegaId = SCOPE_IDENTITY();

INSERT core.PeriodoInventario(EmpresaId, Codigo, FechaInicio, FechaFin)
VALUES (@EmpresaId, '2026-08', '2026-08-01', '2026-08-31');
SET @PeriodoId = SCOPE_IDENTITY();

EXEC inv.usp_ContabilizarEntrada
    @EmpresaId=@EmpresaId, @BodegaId=@BodegaId, @ArticuloId=@ArticuloId,
    @PeriodoInventarioId=@PeriodoId, @FechaMovimiento='2026-08-10T08:00:00', @FechaContable='2026-08-10',
    @TipoMovimiento='COMPRA', @ModuloOrigen='QA', @TipoDocumentoOrigen='RECEPCION',
    @DocumentoOrigenId=1, @NumeroDocumento=N'QA-ENT-1', @CantidadEntrada=10, @CostoUnitarioEntrada=100,
    @IdempotencyKey='11111111-1111-1111-1111-111111111111';

EXEC inv.usp_ContabilizarEntrada
    @EmpresaId=@EmpresaId, @BodegaId=@BodegaId, @ArticuloId=@ArticuloId,
    @PeriodoInventarioId=@PeriodoId, @FechaMovimiento='2026-08-11T08:00:00', @FechaContable='2026-08-11',
    @TipoMovimiento='COMPRA', @ModuloOrigen='QA', @TipoDocumentoOrigen='RECEPCION',
    @DocumentoOrigenId=2, @NumeroDocumento=N'QA-ENT-2', @CantidadEntrada=5, @CostoUnitarioEntrada=130,
    @IdempotencyKey='22222222-2222-2222-2222-222222222222';

-- La misma petición no puede duplicar el movimiento.
EXEC inv.usp_ContabilizarEntrada
    @EmpresaId=@EmpresaId, @BodegaId=@BodegaId, @ArticuloId=@ArticuloId,
    @PeriodoInventarioId=@PeriodoId, @FechaMovimiento='2026-08-11T08:00:00', @FechaContable='2026-08-11',
    @TipoMovimiento='COMPRA', @ModuloOrigen='QA', @TipoDocumentoOrigen='RECEPCION',
    @DocumentoOrigenId=2, @NumeroDocumento=N'QA-ENT-2', @CantidadEntrada=5, @CostoUnitarioEntrada=130,
    @IdempotencyKey='22222222-2222-2222-2222-222222222222';

IF (SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId) <> 2
    THROW 51900, 'La idempotencia de entradas falló.', 1;

IF NOT EXISTS
(
    SELECT 1 FROM inv.SaldoArticuloBodega
    WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId
      AND Existencia=15 AND ValorTotal=1650 AND CostoPromedio=110
)
    THROW 51901, 'El promedio ponderado de entradas es incorrecto.', 1;

EXEC inv.usp_ContabilizarSalida
    @EmpresaId=@EmpresaId, @BodegaId=@BodegaId, @ArticuloId=@ArticuloId,
    @PeriodoInventarioId=@PeriodoId, @FechaMovimiento='2026-08-12T08:00:00', @FechaContable='2026-08-12',
    @TipoMovimiento='VENTA', @ModuloOrigen='QA', @TipoDocumentoOrigen='SALIDA',
    @DocumentoOrigenId=3, @NumeroDocumento=N'QA-SAL-1', @CantidadSalida=3,
    @IdempotencyKey='33333333-3333-3333-3333-333333333333';

IF NOT EXISTS
(
    SELECT 1 FROM inv.SaldoArticuloBodega
    WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId
      AND Existencia=12 AND ValorTotal=1320 AND CostoPromedio=110
)
    THROW 51902, 'La valoración de la salida es incorrecta.', 1;

IF (SELECT COUNT(*) FROM audit.Evento WHERE EmpresaId=@EmpresaId) <> 3
    THROW 51903, 'No se generaron todos los eventos de auditoría.', 1;

IF NOT EXISTS (SELECT 1 FROM sys.triggers WHERE object_id = OBJECT_ID(N'inv.TR_MovimientoInventario_Inmutable'))
    THROW 51904, 'No existe el control de inmutabilidad del Kardex.', 1;

DECLARE @LibroId bigint=(SELECT LibroCostoId FROM cost.LibroCosto WHERE EmpresaId=@EmpresaId AND EsPrincipal=1 AND Estado='ACTIVO');
IF @LibroId IS NULL OR (SELECT COUNT(*) FROM cost.MovimientoCostoLibro WHERE EmpresaId=@EmpresaId AND LibroCostoId=@LibroId)<>3
    THROW 51905, 'El libro operativo no refleja todos los movimientos.', 1;
IF NOT EXISTS(SELECT 1 FROM cost.SaldoCostoLibroBodega WHERE EmpresaId=@EmpresaId AND LibroCostoId=@LibroId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId AND Existencia=12 AND ValorTotal=1320 AND CostoUnitario=110)
    THROW 51906, 'El saldo del libro operativo no coincide con el Kardex.', 1;
DECLARE @Historico TABLE(BodegaId bigint,ArticuloId bigint,Codigo nvarchar(50),Descripcion nvarchar(300),Existencia decimal(20,6),ValorHistorico decimal(38,4),CostoPromedioHistorico decimal(20,8));
INSERT @Historico EXEC inv.usp_ConsultarInventarioAFecha @EmpresaId=@EmpresaId,@FechaCorte='2026-08-10',@BodegaId=@BodegaId,@ArticuloId=@ArticuloId;
IF NOT EXISTS(SELECT 1 FROM @Historico WHERE Existencia=10 AND ValorHistorico=1000 AND CostoPromedioHistorico=100)
    THROW 51907, 'La consulta histórica no reconstruyó el saldo de la fecha solicitada.', 1;

ROLLBACK TRANSACTION;
EXEC sys.sp_set_session_context @key=N'BypassRls', @value=NULL;
PRINT 'QA Kardex correcto: promedio ponderado, salida, idempotencia y auditoría.';
