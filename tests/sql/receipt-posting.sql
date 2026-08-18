SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
BEGIN TRANSACTION;

DECLARE @Suffix varchar(12)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12);
DECLARE @EmpresaId bigint,@UnidadId bigint,@BodegaId bigint,@PeriodoId bigint,@TerceroId bigint,@RecepcionId bigint;
DECLARE @ArticuloA bigint,@ArticuloB bigint;

INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('REC-',@Suffix),CONCAT('6',RIGHT(@Suffix,9)),N'Empresa QA Recepción'); SET @EmpresaId=SCOPE_IDENTITY();
INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);
INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES(@EmpresaId,'UND',N'Unidad','und'); SET @UnidadId=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId) VALUES(@EmpresaId,'A',N'Artículo A','INVENTARIO',1,@UnidadId); SET @ArticuloA=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId) VALUES(@EmpresaId,'B',N'Artículo B','INVENTARIO',1,@UnidadId); SET @ArticuloB=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'BOD',N'Bodega'); SET @BodegaId=SCOPE_IDENTITY();
INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-08','2026-08-01','2026-08-31'); SET @PeriodoId=SCOPE_IDENTITY();
INSERT ter.Tercero(EmpresaId,NumeroIdentificacion,RazonSocial,EsProveedor) VALUES(@EmpresaId,CONCAT('8',RIGHT(@Suffix,9)),N'Proveedor recepción',1); SET @TerceroId=SCOPE_IDENTITY();

INSERT inv.RecepcionMercancia(EmpresaId,Numero,TerceroId,BodegaId,FechaRecepcion,FechaContable,PeriodoInventarioId,Estado)
VALUES(@EmpresaId,CONCAT('REC-',@Suffix),@TerceroId,@BodegaId,SYSUTCDATETIME(),'2026-08-15',@PeriodoId,'VALIDADA');
SET @RecepcionId=SCOPE_IDENTITY();

INSERT inv.RecepcionMercanciaLinea(EmpresaId,RecepcionMercanciaId,NumeroLinea,ArticuloId,UnidadMedidaId,CantidadDocumento,FactorAUnidadBase,CantidadBase,CostoUnitarioDocumento,CostoTotalCapitalizable)
VALUES
(@EmpresaId,@RecepcionId,1,@ArticuloB,@UnidadId,5,1,5,50,250),
(@EmpresaId,@RecepcionId,2,@ArticuloA,@UnidadId,3,1,3,100,300);

EXEC inv.usp_ContabilizarRecepcion @EmpresaId=@EmpresaId,@RecepcionMercanciaId=@RecepcionId;

IF (SELECT Estado FROM inv.RecepcionMercancia WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionId)<>'CONTABILIZADA'
    THROW 51940,'La recepción no quedó contabilizada.',1;
IF (SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND DocumentoOrigenId=@RecepcionId AND TipoDocumentoOrigen='RECEPCION_MERCANCIA')<>2
    THROW 51941,'La recepción no generó exactamente un movimiento por línea.',1;
IF NOT EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloA AND Existencia=3 AND ValorTotal=300)
    THROW 51942,'El saldo del artículo A es incorrecto.',1;
IF NOT EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloB AND Existencia=5 AND ValorTotal=250)
    THROW 51943,'El saldo del artículo B es incorrecto.',1;

EXEC inv.usp_ContabilizarRecepcion @EmpresaId=@EmpresaId,@RecepcionMercanciaId=@RecepcionId;
IF (SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND DocumentoOrigenId=@RecepcionId AND TipoDocumentoOrigen='RECEPCION_MERCANCIA')<>2
    THROW 51944,'El reintento duplicó los movimientos.',1;

ROLLBACK TRANSACTION;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA recepción correcto: contabilización completa, saldos e idempotencia.';
