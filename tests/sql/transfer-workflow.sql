SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
BEGIN TRANSACTION;

DECLARE @Suffix varchar(12)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12);
DECLARE @EmpresaId bigint,@UnidadId bigint,@ArticuloId bigint,@OrigenId bigint,@TransitoId bigint,@DestinoId bigint,@PeriodoId bigint,@TrasladoId bigint;
DECLARE @SaldoInicialKey uniqueidentifier=NEWID();
INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('TRA-',@Suffix),CONCAT('3',RIGHT(@Suffix,9)),N'Empresa QA Traslado'); SET @EmpresaId=SCOPE_IDENTITY();
INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);
INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES(@EmpresaId,'UND',N'Unidad','und'); SET @UnidadId=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId) VALUES(@EmpresaId,'MOTO',N'Motocicleta','INVENTARIO',1,@UnidadId); SET @ArticuloId=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'ORI',N'Origen'); SET @OrigenId=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre,EsTransito) VALUES(@EmpresaId,'TRA',N'Tránsito',1); SET @TransitoId=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'DES',N'Destino'); SET @DestinoId=SCOPE_IDENTITY();
INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-08','2026-08-01','2026-08-31'); SET @PeriodoId=SCOPE_IDENTITY();

EXEC inv.usp_ContabilizarEntrada @EmpresaId=@EmpresaId,@BodegaId=@OrigenId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoId,
 @FechaMovimiento='2026-08-15',@FechaContable='2026-08-15',@TipoMovimiento='SALDO_INICIAL',@ModuloOrigen='QA',
 @TipoDocumentoOrigen='SALDO_INICIAL',@DocumentoOrigenId=1,@NumeroDocumento='SI-QA',@CantidadEntrada=10,@CostoUnitarioEntrada=100,@IdempotencyKey=@SaldoInicialKey;

INSERT inv.Traslado(EmpresaId,Numero,BodegaOrigenId,BodegaTransitoId,BodegaDestinoId,FechaSalida)
VALUES(@EmpresaId,CONCAT('TR-',@Suffix),@OrigenId,@TransitoId,@DestinoId,'2026-08-16'); SET @TrasladoId=SCOPE_IDENTITY();
INSERT inv.TrasladoLinea(EmpresaId,TrasladoId,NumeroLinea,ArticuloId,CantidadDespachada) VALUES(@EmpresaId,@TrasladoId,1,@ArticuloId,4);

EXEC inv.usp_DespacharTraslado @EmpresaId=@EmpresaId,@TrasladoId=@TrasladoId,@PeriodoInventarioId=@PeriodoId,@FechaContable='2026-08-16';
IF NOT EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@OrigenId AND ArticuloId=@ArticuloId AND Existencia=6 AND ValorTotal=600)
    THROW 51960,'La salida de origen del traslado es incorrecta.',1;
IF NOT EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@TransitoId AND ArticuloId=@ArticuloId AND Existencia=4 AND ValorTotal=400)
    THROW 51961,'La entrada a tránsito es incorrecta.',1;

EXEC inv.usp_RecibirTraslado @EmpresaId=@EmpresaId,@TrasladoId=@TrasladoId,@PeriodoInventarioId=@PeriodoId,@FechaContable='2026-08-17',@FechaRecepcion='2026-08-17';
IF NOT EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@TransitoId AND ArticuloId=@ArticuloId AND Existencia=0 AND ValorTotal=0)
    THROW 51962,'La salida de tránsito es incorrecta.',1;
IF NOT EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@DestinoId AND ArticuloId=@ArticuloId AND Existencia=4 AND ValorTotal=400)
    THROW 51963,'La entrada a destino es incorrecta.',1;
IF (SELECT Estado FROM inv.Traslado WHERE EmpresaId=@EmpresaId AND TrasladoId=@TrasladoId)<>'RECIBIDO'
    THROW 51964,'El traslado no quedó recibido.',1;
IF (SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='TRASLADO' AND DocumentoOrigenId=@TrasladoId)<>4
    THROW 51965,'El traslado no generó sus cuatro movimientos relacionados.',1;
IF (SELECT SUM(ValorTotal) FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId)<>1000
    THROW 51966,'El traslado alteró el valor total del inventario.',1;
IF (SELECT COUNT(*) FROM inv.OrigenInventario WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId)<>1
    THROW 51968,'El traslado creó un origen artificial en vez de conservar el original.',1;
IF (SELECT SUM(CantidadDisponible) FROM inv.SaldoOrigenBodega WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId)<>10
    THROW 51969,'La trazabilidad de origen no conserva la cantidad total.',1;
IF NOT EXISTS(SELECT 1 FROM inv.SaldoOrigenBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@DestinoId AND ArticuloId=@ArticuloId AND CantidadDisponible=4)
    THROW 51974,'La existencia recibida no conservó su origen en la bodega destino.',1;

EXEC inv.usp_DespacharTraslado @EmpresaId=@EmpresaId,@TrasladoId=@TrasladoId,@PeriodoInventarioId=@PeriodoId,@FechaContable='2026-08-16';
EXEC inv.usp_RecibirTraslado @EmpresaId=@EmpresaId,@TrasladoId=@TrasladoId,@PeriodoInventarioId=@PeriodoId,@FechaContable='2026-08-17';
IF (SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='TRASLADO' AND DocumentoOrigenId=@TrasladoId)<>4
    THROW 51967,'El reintento duplicó movimientos del traslado.',1;

ROLLBACK TRANSACTION;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA traslado correcto: origen, tránsito, destino, conservación de valor e idempotencia.';
