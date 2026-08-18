SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
BEGIN TRANSACTION;

DECLARE @Suffix varchar(12)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12),@Entrada1Key uniqueidentifier=NEWID(),@VentaKey uniqueidentifier=NEWID(),@Entrada2Key uniqueidentifier=NEWID();
DECLARE @EmpresaId bigint,@UnidadId bigint,@ArticuloId bigint,@BodegaId bigint,@PeriodoId bigint,@VentaMovimientoId bigint,@DevolucionId bigint,@OrigenVentaId bigint;
INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('DVT-',@Suffix),CONCAT('6',RIGHT(@Suffix,9)),N'Empresa QA Devolución venta'); SET @EmpresaId=SCOPE_IDENTITY();
INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);
INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES(@EmpresaId,'UND',N'Unidad','und'); SET @UnidadId=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId) VALUES(@EmpresaId,'A',N'Artículo','INVENTARIO',1,@UnidadId); SET @ArticuloId=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'BOD',N'Bodega'); SET @BodegaId=SCOPE_IDENTITY();
INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-08','2026-08-01','2026-08-31'); SET @PeriodoId=SCOPE_IDENTITY();

EXEC inv.usp_ContabilizarEntrada @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoId,@FechaMovimiento='2026-08-01',@FechaContable='2026-08-01',@TipoMovimiento='COMPRA',@ModuloOrigen='COMPRAS',@TipoDocumentoOrigen='COMPRA_QA',@DocumentoOrigenId=1,@DocumentoLineaOrigenId=1,@NumeroDocumento='C1',@CantidadEntrada=10,@CostoUnitarioEntrada=100,@IdempotencyKey=@Entrada1Key;
DECLARE @Venta TABLE(MovimientoInventarioId bigint,ExistenciaPosterior decimal(20,6),CostoPromedioPosterior decimal(20,8),ValorTotalPosterior decimal(20,4),YaExistia bit);
INSERT @Venta EXEC inv.usp_ContabilizarSalida @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoId,@FechaMovimiento='2026-08-02',@FechaContable='2026-08-02',@TipoMovimiento='VENTA',@ModuloOrigen='VENTAS',@TipoDocumentoOrigen='FACTURA_VENTA',@DocumentoOrigenId=2,@DocumentoLineaOrigenId=1,@NumeroDocumento='FV1',@CantidadSalida=4,@IdempotencyKey=@VentaKey;
SELECT @VentaMovimientoId=MovimientoInventarioId FROM @Venta;
SELECT @OrigenVentaId=OrigenInventarioId FROM inv.MovimientoOrigenInventario WHERE EmpresaId=@EmpresaId AND MovimientoInventarioId=@VentaMovimientoId;
EXEC inv.usp_ContabilizarEntrada @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoId,@FechaMovimiento='2026-08-03',@FechaContable='2026-08-03',@TipoMovimiento='COMPRA',@ModuloOrigen='COMPRAS',@TipoDocumentoOrigen='COMPRA_QA',@DocumentoOrigenId=3,@DocumentoLineaOrigenId=1,@NumeroDocumento='C2',@CantidadEntrada=5,@CostoUnitarioEntrada=200,@IdempotencyKey=@Entrada2Key;

INSERT inv.DevolucionVenta(EmpresaId,Numero,BodegaId,PeriodoInventarioId,FechaMovimiento,FechaContable,Motivo,Estado)
VALUES(@EmpresaId,CONCAT('DV-',@Suffix),@BodegaId,@PeriodoId,'2026-08-04','2026-08-04',N'Devolución parcial del cliente','VALIDADA'); SET @DevolucionId=SCOPE_IDENTITY();
INSERT inv.DevolucionVentaLinea(EmpresaId,DevolucionVentaId,NumeroLinea,MovimientoSalidaOriginalId,ArticuloId,CantidadBase)
VALUES(@EmpresaId,@DevolucionId,1,@VentaMovimientoId,@ArticuloId,2);
EXEC inv.usp_ContabilizarDevolucionVenta @EmpresaId=@EmpresaId,@DevolucionVentaId=@DevolucionId;

IF NOT EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId AND Existencia=13 AND ValorTotal=1800 AND CostoPromedio=138.46153846)
    THROW 51960,'La devolución de venta no se reincorporó al costo original.',1;
IF NOT EXISTS(SELECT 1 FROM inv.DevolucionVentaLinea WHERE EmpresaId=@EmpresaId AND DevolucionVentaId=@DevolucionId AND CostoUnitarioEntrada=100)
    THROW 51961,'La línea no conservó el costo de la salida original.',1;
IF NOT EXISTS(SELECT 1 FROM inv.SaldoOrigenBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId AND OrigenInventarioId=@OrigenVentaId AND CantidadDisponible=8)
    THROW 51962,'La devolución no restituyó el origen consumido por la venta.',1;

EXEC inv.usp_ContabilizarDevolucionVenta @EmpresaId=@EmpresaId,@DevolucionVentaId=@DevolucionId;
IF (SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='DEVOLUCION_VENTA' AND DocumentoOrigenId=@DevolucionId)<>1
    THROW 51963,'El reintento duplicó la devolución de venta.',1;

ROLLBACK TRANSACTION;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA devolución de venta correcto: costo y origen de la salida original restaurados.';
