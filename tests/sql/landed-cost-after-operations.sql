SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
BEGIN TRANSACTION;

DECLARE @Suffix varchar(12)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12),@VentaKey uniqueidentifier=NEWID();
DECLARE @EmpresaId bigint,@UnidadId bigint,@ArticuloId bigint,@OrigenId bigint,@DestinoId bigint,@PeriodoId bigint,@TerceroId bigint,@RecepcionId bigint,@RecepcionLineaId bigint,@TrasladoId bigint,@DevolucionId bigint,@ConceptoId bigint,@DocumentoCostoId bigint,@DistribucionId bigint;
INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('LCT-',@Suffix),CONCAT('7',RIGHT(@Suffix,9)),N'Empresa QA Costo trazable'); SET @EmpresaId=SCOPE_IDENTITY();
INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);
INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES(@EmpresaId,'UND',N'Unidad','und'); SET @UnidadId=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId) VALUES(@EmpresaId,'A',N'Artículo','INVENTARIO',1,@UnidadId); SET @ArticuloId=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'ORI',N'Origen'); SET @OrigenId=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'DES',N'Destino'); SET @DestinoId=SCOPE_IDENTITY();
INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-08','2026-08-01','2026-08-31'); SET @PeriodoId=SCOPE_IDENTITY();
INSERT ter.Tercero(EmpresaId,NumeroIdentificacion,RazonSocial,EsProveedor) VALUES(@EmpresaId,CONCAT('3',RIGHT(@Suffix,9)),N'Proveedor',1); SET @TerceroId=SCOPE_IDENTITY();

INSERT inv.RecepcionMercancia(EmpresaId,Numero,TerceroId,BodegaId,FechaRecepcion,FechaContable,PeriodoInventarioId,Estado)
VALUES(@EmpresaId,CONCAT('REC-',@Suffix),@TerceroId,@OrigenId,'2026-08-10','2026-08-10',@PeriodoId,'VALIDADA'); SET @RecepcionId=SCOPE_IDENTITY();
INSERT inv.RecepcionMercanciaLinea(EmpresaId,RecepcionMercanciaId,NumeroLinea,ArticuloId,UnidadMedidaId,CantidadDocumento,FactorAUnidadBase,CantidadBase,CostoUnitarioDocumento,CostoTotalCapitalizable)
VALUES(@EmpresaId,@RecepcionId,1,@ArticuloId,@UnidadId,10,1,10,100,1000); SET @RecepcionLineaId=SCOPE_IDENTITY();
EXEC inv.usp_ContabilizarRecepcion @EmpresaId=@EmpresaId,@RecepcionMercanciaId=@RecepcionId;

INSERT inv.Traslado(EmpresaId,Numero,BodegaOrigenId,BodegaDestinoId,FechaSalida) VALUES(@EmpresaId,CONCAT('TR-',@Suffix),@OrigenId,@DestinoId,'2026-08-11'); SET @TrasladoId=SCOPE_IDENTITY();
INSERT inv.TrasladoLinea(EmpresaId,TrasladoId,NumeroLinea,ArticuloId,CantidadDespachada) VALUES(@EmpresaId,@TrasladoId,1,@ArticuloId,4);
EXEC inv.usp_DespacharTraslado @EmpresaId=@EmpresaId,@TrasladoId=@TrasladoId,@PeriodoInventarioId=@PeriodoId,@FechaContable='2026-08-11';
EXEC inv.usp_RecibirTraslado @EmpresaId=@EmpresaId,@TrasladoId=@TrasladoId,@PeriodoInventarioId=@PeriodoId,@FechaContable='2026-08-11';

EXEC inv.usp_ContabilizarSalida @EmpresaId=@EmpresaId,@BodegaId=@OrigenId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoId,@FechaMovimiento='2026-08-12',@FechaContable='2026-08-12',@TipoMovimiento='VENTA',@ModuloOrigen='VENTAS',@TipoDocumentoOrigen='FACTURA_VENTA',@DocumentoOrigenId=100,@NumeroDocumento='FV-QA',@CantidadSalida=3,@IdempotencyKey=@VentaKey;

INSERT inv.DevolucionProveedor(EmpresaId,Numero,TerceroId,BodegaId,PeriodoInventarioId,FechaMovimiento,FechaContable,Motivo,Estado)
VALUES(@EmpresaId,CONCAT('DEV-',@Suffix),@TerceroId,@DestinoId,@PeriodoId,'2026-08-13','2026-08-13',N'No conformidad','VALIDADA'); SET @DevolucionId=SCOPE_IDENTITY();
INSERT inv.DevolucionProveedorLinea(EmpresaId,DevolucionProveedorId,NumeroLinea,RecepcionMercanciaLineaId,ArticuloId,CantidadBase)
VALUES(@EmpresaId,@DevolucionId,1,@RecepcionLineaId,@ArticuloId,1);
EXEC inv.usp_ContabilizarDevolucionProveedor @EmpresaId=@EmpresaId,@DevolucionProveedorId=@DevolucionId;

INSERT cost.ConceptoCostoAdquisicion(EmpresaId,Codigo,Nombre,Tratamiento,MetodoDistribucionDefecto) VALUES(@EmpresaId,'FLETE',N'Flete','CAPITALIZABLE','VALOR_COMPRA'); SET @ConceptoId=SCOPE_IDENTITY();
INSERT cost.DocumentoCostoAdquisicion(EmpresaId,ConceptoCostoId,TerceroId,NumeroSoporte,FechaDocumento,ValorDistribuible,Estado) VALUES(@EmpresaId,@ConceptoId,@TerceroId,CONCAT('FLT-',@Suffix),'2026-08-14',200,'APROBADO'); SET @DocumentoCostoId=SCOPE_IDENTITY();
INSERT cost.DistribucionCosto(EmpresaId,DocumentoCostoId,Metodo,ValorTotal,BaseTotal) VALUES(@EmpresaId,@DocumentoCostoId,'VALOR_COMPRA',200,0); SET @DistribucionId=SCOPE_IDENTITY();
INSERT cost.DistribucionCostoObjetivo(EmpresaId,DistribucionCostoId,RecepcionMercanciaLineaId) VALUES(@EmpresaId,@DistribucionId,@RecepcionLineaId);
EXEC cost.usp_CalcularDistribucionCosto @EmpresaId=@EmpresaId,@DistribucionCostoId=@DistribucionId;
EXEC cost.usp_AplicarDistribucionCosto @EmpresaId=@EmpresaId,@DistribucionCostoId=@DistribucionId,@PeriodoInventarioId=@PeriodoId,@FechaContable='2026-08-14';

IF NOT EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@OrigenId AND ArticuloId=@ArticuloId AND Existencia=3 AND ValorTotal=360 AND CostoPromedio=120)
    THROW 51933,'El costo tardío no ajustó correctamente la existencia en origen.',1;
IF NOT EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@DestinoId AND ArticuloId=@ArticuloId AND Existencia=3 AND ValorTotal=360 AND CostoPromedio=120)
    THROW 51934,'El costo tardío no siguió la mercancía trasladada.',1;
IF (SELECT SUM(ValorAplicado) FROM cost.AplicacionCostoAdquisicion a JOIN cost.DistribucionCostoLinea l ON l.EmpresaId=a.EmpresaId AND l.DistribucionCostoLineaId=a.DistribucionCostoLineaId WHERE l.EmpresaId=@EmpresaId AND l.DistribucionCostoId=@DistribucionId)<>200
    THROW 51935,'Las aplicaciones del costo tardío no reconcilian.',1;
IF NOT EXISTS(SELECT 1 FROM cost.AplicacionCostoAdquisicion a JOIN cost.DistribucionCostoLinea l ON l.EmpresaId=a.EmpresaId AND l.DistribucionCostoLineaId=a.DistribucionCostoLineaId WHERE l.EmpresaId=@EmpresaId AND l.DistribucionCostoId=@DistribucionId AND a.TipoDestino='DEVOLUCION_PROVEEDOR' AND a.CantidadAtribuida=1 AND a.ValorAplicado=20)
    THROW 51936,'La porción devuelta no quedó separada.',1;
IF NOT EXISTS(SELECT 1 FROM cost.AplicacionCostoAdquisicion a JOIN cost.DistribucionCostoLinea l ON l.EmpresaId=a.EmpresaId AND l.DistribucionCostoLineaId=a.DistribucionCostoLineaId WHERE l.EmpresaId=@EmpresaId AND l.DistribucionCostoId=@DistribucionId AND a.TipoDestino='RESULTADO_PERIODO' AND a.CantidadAtribuida=3 AND a.ValorAplicado=60)
    THROW 51937,'La porción ya vendida no quedó reconocida en resultado.',1;
IF (SELECT COUNT(*) FROM cost.AplicacionCostoAdquisicion a JOIN cost.DistribucionCostoLinea l ON l.EmpresaId=a.EmpresaId AND l.DistribucionCostoLineaId=a.DistribucionCostoLineaId WHERE l.EmpresaId=@EmpresaId AND l.DistribucionCostoId=@DistribucionId AND a.TipoDestino='INVENTARIO' AND a.ValorAplicado=60)<>2
    THROW 51938,'El costo de las existencias no se distribuyó entre ambas bodegas.',1;
IF (SELECT COUNT(*) FROM core.OutboxEvento WHERE EmpresaId=@EmpresaId AND TipoEvento=N'Costos.VariacionAdquisicionReconocida')<>2
    THROW 51939,'Las variaciones de devolución y resultado no generaron sus eventos contables.',1;

ROLLBACK TRANSACTION;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA costo tardío trazable correcto: traslado, venta, devolución e inventario reconcilian.';
