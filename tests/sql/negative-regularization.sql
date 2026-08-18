SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
BEGIN TRANSACTION;

DECLARE @Suffix varchar(12)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12),@InicialKey uniqueidentifier=NEWID(),@ExcepcionKey uniqueidentifier=NEWID();
DECLARE @EmpresaId bigint,@UnidadId bigint,@ArticuloId bigint,@BodegaId bigint,@PeriodoId bigint,@TerceroId bigint,@RecepcionId bigint,@RecepcionLineaId bigint,@UsuarioId bigint,@RolId bigint,@ExcepcionId bigint;
INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('NEG-',@Suffix),CONCAT('2',RIGHT(@Suffix,9)),N'Empresa QA Negativos'); SET @EmpresaId=SCOPE_IDENTITY();
INSERT core.EmpresaConfiguracion(EmpresaId,PermiteInventarioNegativo) VALUES(@EmpresaId,1);
INSERT seg.Usuario(Correo,NombreCompleto) VALUES(CONCAT('qa-',@Suffix,'@erp.local'),N'Autorizador QA'); SET @UsuarioId=SCOPE_IDENTITY();
INSERT seg.Rol(Codigo,Nombre) VALUES(CONCAT('AUTNEG-',@Suffix),N'Autoriza negativos'); SET @RolId=SCOPE_IDENTITY();
INSERT seg.UsuarioEmpresaRol(EmpresaId,UsuarioId,RolId) VALUES(@EmpresaId,@UsuarioId,@RolId);
INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES(@EmpresaId,'UND',N'Unidad','und'); SET @UnidadId=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId) VALUES(@EmpresaId,'A',N'Artículo','INVENTARIO',1,@UnidadId); SET @ArticuloId=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'BOD',N'Bodega'); SET @BodegaId=SCOPE_IDENTITY();
INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-08','2026-08-01','2026-08-31'); SET @PeriodoId=SCOPE_IDENTITY();
INSERT ter.Tercero(EmpresaId,NumeroIdentificacion,RazonSocial,EsProveedor) VALUES(@EmpresaId,CONCAT('8',RIGHT(@Suffix,9)),N'Proveedor',1); SET @TerceroId=SCOPE_IDENTITY();
EXEC inv.usp_ContabilizarEntrada @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoId,@FechaMovimiento='2026-08-01',@FechaContable='2026-08-01',@TipoMovimiento='SALDO_INICIAL',@ModuloOrigen='QA',@TipoDocumentoOrigen='SALDO_INICIAL',@DocumentoOrigenId=1,@NumeroDocumento='SI',@CantidadEntrada=2,@CostoUnitarioEntrada=100,@IdempotencyKey=@InicialKey;

EXEC inv.usp_RegistrarSalidaExcepcionalNegativa @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoId,@FechaMovimiento='2026-08-02',@FechaContable='2026-08-02',@TipoDocumentoOrigen='FACTURA_VENTA',@DocumentoOrigenId=10,@NumeroDocumento='FV-NEG',@CantidadSolicitada=5,@Motivo=N'Entrega autorizada antes de recibir la compra',@AutorizadoPorUsuarioId=@UsuarioId,@IdempotencyKey=@ExcepcionKey;
SELECT @ExcepcionId=SalidaExcepcionalNegativaId FROM inv.SalidaExcepcionalNegativa WHERE EmpresaId=@EmpresaId AND IdempotencyKey=@ExcepcionKey;
IF NOT EXISTS(SELECT 1 FROM inv.vw_DisponibilidadArticuloBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId AND ExistenciaValorizada=0 AND SalidaPendienteRegularizar=3 AND DisponibilidadOperativa=-3)
    THROW 51980,'La disponibilidad operativa excepcional es incorrecta.',1;

INSERT inv.RecepcionMercancia(EmpresaId,Numero,TerceroId,BodegaId,FechaRecepcion,FechaContable,PeriodoInventarioId,Estado)
VALUES(@EmpresaId,CONCAT('REC-',@Suffix),@TerceroId,@BodegaId,'2026-08-03','2026-08-03',@PeriodoId,'VALIDADA'); SET @RecepcionId=SCOPE_IDENTITY();
INSERT inv.RecepcionMercanciaLinea(EmpresaId,RecepcionMercanciaId,NumeroLinea,ArticuloId,UnidadMedidaId,CantidadDocumento,FactorAUnidadBase,CantidadBase,CostoUnitarioDocumento,CostoTotalCapitalizable)
VALUES(@EmpresaId,@RecepcionId,1,@ArticuloId,@UnidadId,10,1,10,120,1200); SET @RecepcionLineaId=SCOPE_IDENTITY();
EXEC inv.usp_ContabilizarRecepcion @EmpresaId=@EmpresaId,@RecepcionMercanciaId=@RecepcionId;
EXEC inv.usp_RegularizarSalidaExcepcionalNegativa @EmpresaId=@EmpresaId,@SalidaExcepcionalNegativaId=@ExcepcionId,@RecepcionMercanciaLineaId=@RecepcionLineaId,@PeriodoInventarioId=@PeriodoId,@FechaContable='2026-08-03',@UsuarioId=@UsuarioId;

IF NOT EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId AND Existencia=7 AND ValorTotal=840 AND CostoPromedio=120)
    THROW 51981,'La regularización no valorizó al costo real de la recepción.',1;
IF NOT EXISTS(SELECT 1 FROM inv.SalidaExcepcionalNegativa WHERE EmpresaId=@EmpresaId AND SalidaExcepcionalNegativaId=@ExcepcionId AND Estado='REGULARIZADA' AND CantidadValorizada=2 AND CantidadPendiente=3 AND RecepcionMercanciaLineaId=@RecepcionLineaId)
    THROW 51982,'La salida excepcional no conservó su trazabilidad completa.',1;
IF NOT EXISTS(SELECT 1 FROM inv.OrigenInventario o JOIN inv.SaldoOrigenBodega s ON s.EmpresaId=o.EmpresaId AND s.OrigenInventarioId=o.OrigenInventarioId WHERE o.EmpresaId=@EmpresaId AND o.RecepcionMercanciaLineaId=@RecepcionLineaId AND s.BodegaId=@BodegaId AND s.CantidadDisponible=7)
    THROW 51983,'La regularización no consumió el origen de la recepción seleccionada.',1;

EXEC inv.usp_RegularizarSalidaExcepcionalNegativa @EmpresaId=@EmpresaId,@SalidaExcepcionalNegativaId=@ExcepcionId,@RecepcionMercanciaLineaId=@RecepcionLineaId,@PeriodoInventarioId=@PeriodoId,@FechaContable='2026-08-03',@UsuarioId=@UsuarioId;
IF (SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='REGULARIZACION_NEGATIVO' AND DocumentoOrigenId=@ExcepcionId)<>1
    THROW 51984,'El reintento duplicó la regularización.',1;

ROLLBACK TRANSACTION;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA negativo correcto: pendiente no valorizado y regularización al costo real posterior.';
