SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
BEGIN TRANSACTION;

DECLARE @Suffix varchar(12)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12);
DECLARE @EmpresaId bigint,@UnidadId bigint,@ArticuloId bigint,@BodegaId bigint,@PeriodoId bigint,@TerceroId bigint,@RecepcionId bigint,@RecepcionLineaId bigint,@ConceptoId bigint,@DocumentoCostoId bigint,@DistribucionId bigint;
INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('APL-',@Suffix),CONCAT('9',RIGHT(@Suffix,9)),N'Empresa QA Aplicación costo'); SET @EmpresaId=SCOPE_IDENTITY();
INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);
INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES(@EmpresaId,'UND',N'Unidad','und'); SET @UnidadId=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId) VALUES(@EmpresaId,'A',N'Artículo importado','INVENTARIO',1,@UnidadId); SET @ArticuloId=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'BOD',N'Bodega'); SET @BodegaId=SCOPE_IDENTITY();
INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-08','2026-08-01','2026-08-31'); SET @PeriodoId=SCOPE_IDENTITY();
INSERT ter.Tercero(EmpresaId,NumeroIdentificacion,RazonSocial,EsProveedor) VALUES(@EmpresaId,CONCAT('6',RIGHT(@Suffix,9)),N'Proveedor flete',1); SET @TerceroId=SCOPE_IDENTITY();
INSERT inv.RecepcionMercancia(EmpresaId,Numero,TerceroId,BodegaId,FechaRecepcion,FechaContable,PeriodoInventarioId,Estado)
VALUES(@EmpresaId,CONCAT('REC-',@Suffix),@TerceroId,@BodegaId,'2026-08-15','2026-08-15',@PeriodoId,'VALIDADA'); SET @RecepcionId=SCOPE_IDENTITY();
INSERT inv.RecepcionMercanciaLinea(EmpresaId,RecepcionMercanciaId,NumeroLinea,ArticuloId,UnidadMedidaId,CantidadDocumento,FactorAUnidadBase,CantidadBase,CostoUnitarioDocumento,CostoTotalCapitalizable)
VALUES(@EmpresaId,@RecepcionId,1,@ArticuloId,@UnidadId,10,1,10,100,1000); SET @RecepcionLineaId=SCOPE_IDENTITY();
EXEC inv.usp_ContabilizarRecepcion @EmpresaId=@EmpresaId,@RecepcionMercanciaId=@RecepcionId;

INSERT cost.ConceptoCostoAdquisicion(EmpresaId,Codigo,Nombre,Tratamiento,MetodoDistribucionDefecto) VALUES(@EmpresaId,'FLETE',N'Flete','CAPITALIZABLE','VALOR_COMPRA'); SET @ConceptoId=SCOPE_IDENTITY();
INSERT cost.DocumentoCostoAdquisicion(EmpresaId,ConceptoCostoId,TerceroId,NumeroSoporte,FechaDocumento,ValorDistribuible,Estado) VALUES(@EmpresaId,@ConceptoId,@TerceroId,CONCAT('FLT-',@Suffix),'2026-08-16',200,'APROBADO'); SET @DocumentoCostoId=SCOPE_IDENTITY();
INSERT cost.DistribucionCosto(EmpresaId,DocumentoCostoId,Metodo,ValorTotal,BaseTotal) VALUES(@EmpresaId,@DocumentoCostoId,'VALOR_COMPRA',200,0); SET @DistribucionId=SCOPE_IDENTITY();
INSERT cost.DistribucionCostoObjetivo(EmpresaId,DistribucionCostoId,RecepcionMercanciaLineaId) VALUES(@EmpresaId,@DistribucionId,@RecepcionLineaId);
EXEC cost.usp_CalcularDistribucionCosto @EmpresaId=@EmpresaId,@DistribucionCostoId=@DistribucionId;
EXEC cost.usp_AplicarDistribucionCosto @EmpresaId=@EmpresaId,@DistribucionCostoId=@DistribucionId,@PeriodoInventarioId=@PeriodoId,@FechaContable='2026-08-16';

IF NOT EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId AND Existencia=10 AND ValorTotal=1200 AND CostoPromedio=120)
    THROW 51990,'El costo adicional tardío no actualizó valor y promedio.',1;
IF NOT EXISTS(SELECT 1 FROM inv.RecepcionMercanciaLinea WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaLineaId=@RecepcionLineaId AND CostoAdicionalAsignado=200 AND CostoTotalCapitalizable=1200)
    THROW 51991,'La línea de recepción no refleja el costo adicional.',1;
IF (SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='DISTRIBUCION_COSTO' AND DocumentoOrigenId=@DistribucionId)<>1
    THROW 51992,'La aplicación tardía no generó un único ajuste de valor.',1;

EXEC cost.usp_AplicarDistribucionCosto @EmpresaId=@EmpresaId,@DistribucionCostoId=@DistribucionId,@PeriodoInventarioId=@PeriodoId,@FechaContable='2026-08-16';
IF (SELECT ValorTotal FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId)<>1200
    THROW 51993,'El reintento duplicó el costo adicional.',1;

ROLLBACK TRANSACTION;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA aplicación costo correcto: ajuste tardío de valor, promedio e idempotencia.';
