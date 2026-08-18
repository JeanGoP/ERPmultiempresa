SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
BEGIN TRANSACTION;

DECLARE @Suffix varchar(12)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12);
DECLARE @EmpresaId bigint,@UnidadId bigint,@BodegaId bigint,@PeriodoId bigint,@TerceroId bigint,@RecepcionId bigint;
DECLARE @ArticuloA bigint,@ArticuloB bigint,@ArticuloC bigint;
DECLARE @LineaA bigint,@LineaB bigint,@LineaC bigint,@ConceptoId bigint,@DocumentoCostoId bigint,@DistribucionId bigint;

INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('CST-',@Suffix),CONCAT('5',RIGHT(@Suffix,9)),N'Empresa QA Costos'); SET @EmpresaId=SCOPE_IDENTITY();
INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);
INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES(@EmpresaId,'UND',N'Unidad','und'); SET @UnidadId=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId) VALUES(@EmpresaId,'A',N'Artículo A','INVENTARIO',1,@UnidadId); SET @ArticuloA=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId) VALUES(@EmpresaId,'B',N'Artículo B','INVENTARIO',1,@UnidadId); SET @ArticuloB=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId) VALUES(@EmpresaId,'C',N'Artículo C','INVENTARIO',1,@UnidadId); SET @ArticuloC=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'BOD',N'Bodega'); SET @BodegaId=SCOPE_IDENTITY();
INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-08','2026-08-01','2026-08-31'); SET @PeriodoId=SCOPE_IDENTITY();
INSERT ter.Tercero(EmpresaId,NumeroIdentificacion,RazonSocial,EsProveedor) VALUES(@EmpresaId,CONCAT('9',RIGHT(@Suffix,9)),N'Proveedor costo',1); SET @TerceroId=SCOPE_IDENTITY();
INSERT inv.RecepcionMercancia(EmpresaId,Numero,TerceroId,BodegaId,FechaRecepcion,FechaContable,PeriodoInventarioId) VALUES(@EmpresaId,'REC-CST',@TerceroId,@BodegaId,SYSUTCDATETIME(),'2026-08-15',@PeriodoId); SET @RecepcionId=SCOPE_IDENTITY();

INSERT inv.RecepcionMercanciaLinea(EmpresaId,RecepcionMercanciaId,NumeroLinea,ArticuloId,UnidadMedidaId,CantidadDocumento,FactorAUnidadBase,CantidadBase,CostoUnitarioDocumento,CostoTotalCapitalizable)
VALUES(@EmpresaId,@RecepcionId,1,@ArticuloA,@UnidadId,10,1,10,100,1000); SET @LineaA=SCOPE_IDENTITY();
INSERT inv.RecepcionMercanciaLinea(EmpresaId,RecepcionMercanciaId,NumeroLinea,ArticuloId,UnidadMedidaId,CantidadDocumento,FactorAUnidadBase,CantidadBase,CostoUnitarioDocumento,CostoTotalCapitalizable)
VALUES(@EmpresaId,@RecepcionId,2,@ArticuloB,@UnidadId,50,1,50,20,1000); SET @LineaB=SCOPE_IDENTITY();
INSERT inv.RecepcionMercanciaLinea(EmpresaId,RecepcionMercanciaId,NumeroLinea,ArticuloId,UnidadMedidaId,CantidadDocumento,FactorAUnidadBase,CantidadBase,CostoUnitarioDocumento,CostoTotalCapitalizable)
VALUES(@EmpresaId,@RecepcionId,3,@ArticuloC,@UnidadId,5,1,5,500,2500); SET @LineaC=SCOPE_IDENTITY();

INSERT cost.ConceptoCostoAdquisicion(EmpresaId,Codigo,Nombre,Tratamiento,MetodoDistribucionDefecto) VALUES(@EmpresaId,'FLETE',N'Flete','CAPITALIZABLE','VALOR_COMPRA'); SET @ConceptoId=SCOPE_IDENTITY();
INSERT cost.DocumentoCostoAdquisicion(EmpresaId,ConceptoCostoId,TerceroId,NumeroSoporte,FechaDocumento,ValorDistribuible) VALUES(@EmpresaId,@ConceptoId,@TerceroId,'FLETE-QA','2026-08-15',500.0001); SET @DocumentoCostoId=SCOPE_IDENTITY();
INSERT cost.DistribucionCosto(EmpresaId,DocumentoCostoId,Metodo,ValorTotal,BaseTotal) VALUES(@EmpresaId,@DocumentoCostoId,'VALOR_COMPRA',500.0001,0); SET @DistribucionId=SCOPE_IDENTITY();
INSERT cost.DistribucionCostoObjetivo(EmpresaId,DistribucionCostoId,RecepcionMercanciaLineaId) VALUES(@EmpresaId,@DistribucionId,@LineaA),(@EmpresaId,@DistribucionId,@LineaB),(@EmpresaId,@DistribucionId,@LineaC);

EXEC cost.usp_CalcularDistribucionCosto @EmpresaId=@EmpresaId,@DistribucionCostoId=@DistribucionId;

IF (SELECT SUM(ValorAsignado) FROM cost.DistribucionCostoLinea WHERE EmpresaId=@EmpresaId AND DistribucionCostoId=@DistribucionId)<>500.0001
    THROW 51930,'El prorrateo no coincide exactamente con el flete.',1;
IF (SELECT COUNT(*) FROM cost.DistribucionCostoLinea WHERE EmpresaId=@EmpresaId AND DistribucionCostoId=@DistribucionId)<>3
    THROW 51931,'El prorrateo no incluyó todos los artículos.',1;
IF NOT EXISTS(SELECT 1 FROM cost.DistribucionCostoLinea WHERE EmpresaId=@EmpresaId AND DistribucionCostoId=@DistribucionId AND EsLineaAjusteRedondeo=1 AND ValorAsignado=277.7779)
    THROW 51932,'El residuo de redondeo no se asignó de forma determinística.',1;

ROLLBACK TRANSACTION;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA costos correcto: prorrateo por valor y reconciliación exacta del redondeo.';
