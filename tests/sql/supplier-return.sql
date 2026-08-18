SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
BEGIN TRANSACTION;

DECLARE @Suffix varchar(12)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12);
DECLARE @EmpresaId bigint,@UnidadId bigint,@ArticuloId bigint,@BodegaId bigint,@PeriodoId bigint,@TerceroId bigint,@RecepcionId bigint,@Recepcion2Id bigint,@RecepcionLineaId bigint,@DevolucionId bigint;
INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('DEV-',@Suffix),CONCAT('2',RIGHT(@Suffix,9)),N'Empresa QA Devolución'); SET @EmpresaId=SCOPE_IDENTITY();
INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);
INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES(@EmpresaId,'UND',N'Unidad','und'); SET @UnidadId=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId) VALUES(@EmpresaId,'REP',N'Repuesto','INVENTARIO',1,@UnidadId); SET @ArticuloId=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'BOD',N'Bodega'); SET @BodegaId=SCOPE_IDENTITY();
INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-08','2026-08-01','2026-08-31'); SET @PeriodoId=SCOPE_IDENTITY();
INSERT ter.Tercero(EmpresaId,NumeroIdentificacion,RazonSocial,EsProveedor) VALUES(@EmpresaId,CONCAT('1',RIGHT(@Suffix,9)),N'Proveedor devolución',1); SET @TerceroId=SCOPE_IDENTITY();
INSERT inv.RecepcionMercancia(EmpresaId,Numero,TerceroId,BodegaId,FechaRecepcion,FechaContable,PeriodoInventarioId,Estado)
VALUES(@EmpresaId,CONCAT('REC-',@Suffix),@TerceroId,@BodegaId,'2026-08-15','2026-08-15',@PeriodoId,'VALIDADA'); SET @RecepcionId=SCOPE_IDENTITY();
INSERT inv.RecepcionMercanciaLinea(EmpresaId,RecepcionMercanciaId,NumeroLinea,ArticuloId,UnidadMedidaId,CantidadDocumento,FactorAUnidadBase,CantidadBase,CostoUnitarioDocumento,CostoTotalCapitalizable)
VALUES(@EmpresaId,@RecepcionId,1,@ArticuloId,@UnidadId,10,1,10,80,800); SET @RecepcionLineaId=SCOPE_IDENTITY();
EXEC inv.usp_ContabilizarRecepcion @EmpresaId=@EmpresaId,@RecepcionMercanciaId=@RecepcionId;

INSERT inv.RecepcionMercancia(EmpresaId,Numero,TerceroId,BodegaId,FechaRecepcion,FechaContable,PeriodoInventarioId,Estado)
VALUES(@EmpresaId,CONCAT('REC2-',@Suffix),@TerceroId,@BodegaId,'2026-08-16','2026-08-16',@PeriodoId,'VALIDADA'); SET @Recepcion2Id=SCOPE_IDENTITY();
INSERT inv.RecepcionMercanciaLinea(EmpresaId,RecepcionMercanciaId,NumeroLinea,ArticuloId,UnidadMedidaId,CantidadDocumento,FactorAUnidadBase,CantidadBase,CostoUnitarioDocumento,CostoTotalCapitalizable)
VALUES(@EmpresaId,@Recepcion2Id,1,@ArticuloId,@UnidadId,10,1,10,160,1600);
EXEC inv.usp_ContabilizarRecepcion @EmpresaId=@EmpresaId,@RecepcionMercanciaId=@Recepcion2Id;

INSERT inv.DevolucionProveedor(EmpresaId,Numero,TerceroId,BodegaId,PeriodoInventarioId,FechaMovimiento,FechaContable,Motivo,Estado)
VALUES(@EmpresaId,CONCAT('DEV-',@Suffix),@TerceroId,@BodegaId,@PeriodoId,'2026-08-18','2026-08-18',N'Producto no conforme','VALIDADA'); SET @DevolucionId=SCOPE_IDENTITY();
INSERT inv.DevolucionProveedorLinea(EmpresaId,DevolucionProveedorId,NumeroLinea,RecepcionMercanciaLineaId,ArticuloId,CantidadBase)
VALUES(@EmpresaId,@DevolucionId,1,@RecepcionLineaId,@ArticuloId,2);
EXEC inv.usp_ContabilizarDevolucionProveedor @EmpresaId=@EmpresaId,@DevolucionProveedorId=@DevolucionId;

IF NOT EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId AND Existencia=18 AND ValorTotal=2240 AND CostoPromedio=124.44444444)
    THROW 51970,'La devolución no actualizó correctamente el saldo.',1;
IF (SELECT Estado FROM inv.DevolucionProveedor WHERE EmpresaId=@EmpresaId AND DevolucionProveedorId=@DevolucionId)<>'CONTABILIZADA'
    THROW 51971,'La devolución no quedó contabilizada.',1;
IF NOT EXISTS(SELECT 1 FROM inv.DevolucionProveedorLinea WHERE EmpresaId=@EmpresaId AND DevolucionProveedorId=@DevolucionId AND CostoUnitarioSalida=80)
    THROW 51972,'La devolución no conservó el costo de salida.',1;
IF NOT EXISTS(SELECT 1 FROM inv.OrigenInventario o JOIN inv.SaldoOrigenBodega s ON s.EmpresaId=o.EmpresaId AND s.OrigenInventarioId=o.OrigenInventarioId WHERE o.EmpresaId=@EmpresaId AND o.RecepcionMercanciaLineaId=@RecepcionLineaId AND s.BodegaId=@BodegaId AND s.CantidadDisponible=8)
    THROW 51975,'La devolución no descontó la recepción original en la trazabilidad de origen.',1;

EXEC inv.usp_ContabilizarDevolucionProveedor @EmpresaId=@EmpresaId,@DevolucionProveedorId=@DevolucionId;
IF (SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='DEVOLUCION_PROVEEDOR' AND DocumentoOrigenId=@DevolucionId)<>1
    THROW 51973,'El reintento duplicó la devolución.',1;

ROLLBACK TRANSACTION;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA devolución correcto: vínculo con recepción, costo promedio e idempotencia.';
