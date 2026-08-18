SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
BEGIN TRANSACTION;

DECLARE @Suffix varchar(12)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12),@Key uniqueidentifier=NEWID();
DECLARE @EmpresaId bigint,@UnidadId bigint,@ArticuloId bigint,@BodegaId bigint,@PeriodoId bigint,@DeterioroId bigint;
INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('OUT-',@Suffix),CONCAT('4',RIGHT(@Suffix,9)),N'Empresa QA Outbox'); SET @EmpresaId=SCOPE_IDENTITY();
INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);
INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES(@EmpresaId,'UND',N'Unidad','und'); SET @UnidadId=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId) VALUES(@EmpresaId,'A',N'Artículo','INVENTARIO',1,@UnidadId); SET @ArticuloId=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'BOD',N'Bodega'); SET @BodegaId=SCOPE_IDENTITY();
INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-08','2026-08-01','2026-08-31'); SET @PeriodoId=SCOPE_IDENTITY();
EXEC inv.usp_ContabilizarEntrada @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoId,@FechaMovimiento='2026-08-10',@FechaContable='2026-08-10',@TipoMovimiento='SALDO_INICIAL',@ModuloOrigen='QA',@TipoDocumentoOrigen='SALDO_INICIAL',@DocumentoOrigenId=1,@NumeroDocumento='SI',@CantidadEntrada=10,@CostoUnitarioEntrada=100,@IdempotencyKey=@Key;
IF NOT EXISTS(SELECT 1 FROM core.OutboxEvento WHERE EmpresaId=@EmpresaId AND TipoEvento=N'Inventario.MovimientoRegistrado' AND JSON_VALUE(Payload,'$.articuloId')=CONVERT(varchar(30),@ArticuloId))
    THROW 51930,'El movimiento no generó evento Outbox.',1;

EXEC inv.usp_RegistrarDeterioroInventario @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoId,@Tipo='DETERIORO',@ValorNetoRealizable=850,@Motivo=N'Disminución comprobada del valor neto realizable';
SELECT @DeterioroId=MAX(DeterioroInventarioId) FROM inv.DeterioroInventario WHERE EmpresaId=@EmpresaId;
IF NOT EXISTS(SELECT 1 FROM inv.DeterioroInventario WHERE EmpresaId=@EmpresaId AND DeterioroInventarioId=@DeterioroId AND CostoHistorico=1000 AND ValorDeterioro=150 AND SaldoDeterioroPosterior=150)
    THROW 51931,'El deterioro calculado es incorrecto.',1;
IF NOT EXISTS(SELECT 1 FROM core.OutboxEvento WHERE EmpresaId=@EmpresaId AND TipoEvento=N'Inventario.DeterioroRegistrado' AND AgregadoId=CONVERT(nvarchar(100),@DeterioroId))
    THROW 51932,'El deterioro no generó evento Outbox.',1;

EXEC inv.usp_RegistrarDeterioroInventario @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoId,@Tipo='DETERIORO',@ValorNetoRealizable=800,@Motivo=N'Nueva evidencia reduce adicionalmente el valor recuperable';
DECLARE @SegundoId bigint=(SELECT MAX(DeterioroInventarioId) FROM inv.DeterioroInventario WHERE EmpresaId=@EmpresaId);
IF NOT EXISTS(SELECT 1 FROM inv.DeterioroInventario WHERE EmpresaId=@EmpresaId AND DeterioroInventarioId=@SegundoId AND ValorDeterioro=50 AND SaldoDeterioroAnterior=150 AND SaldoDeterioroPosterior=200)
    THROW 51933,'El deterioro incremental duplicó el saldo previo.',1;
EXEC inv.usp_RegistrarDeterioroInventario @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoId,@Tipo='REVERSA',@ValorNetoRealizable=70,@Motivo=N'Recuperación demostrable del valor neto realizable',@DeterioroRelacionadoId=@SegundoId;
IF NOT EXISTS(SELECT 1 FROM inv.vw_ValorNetoInventario WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId AND CostoHistorico=1000 AND DeterioroAcumulado=130 AND ValorNetoContable=870)
    THROW 51934,'La reversa no conservó costo histórico, deterioro acumulado y valor neto.',1;
IF (SELECT COUNT(*) FROM core.OutboxEvento WHERE EmpresaId=@EmpresaId AND TipoEvento=N'Inventario.DeterioroRegistrado')<>3
    THROW 51935,'Los cambios de deterioro no generaron todos sus eventos.',1;

ROLLBACK TRANSACTION;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA Outbox correcto: movimiento y deterioro generan eventos atómicos.';
