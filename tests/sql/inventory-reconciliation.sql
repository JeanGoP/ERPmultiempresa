SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
BEGIN TRANSACTION;

DECLARE @Suffix varchar(12)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12),@Key uniqueidentifier=NEWID();
DECLARE @EmpresaId bigint,@UnidadId bigint,@ArticuloId bigint,@BodegaId bigint,@PeriodoId bigint,@OrigenId bigint;
INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('RCN-',@Suffix),CONCAT('1',RIGHT(@Suffix,9)),N'Empresa QA Reconciliación'); SET @EmpresaId=SCOPE_IDENTITY();
INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);
INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES(@EmpresaId,'UND',N'Unidad','und'); SET @UnidadId=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId) VALUES(@EmpresaId,'A',N'Artículo','INVENTARIO',1,@UnidadId); SET @ArticuloId=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'BOD',N'Bodega'); SET @BodegaId=SCOPE_IDENTITY();
INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-08','2026-08-01','2026-08-31'); SET @PeriodoId=SCOPE_IDENTITY();
EXEC inv.usp_ContabilizarEntrada @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoId,@FechaMovimiento='2026-08-10',@FechaContable='2026-08-10',@TipoMovimiento='SALDO_INICIAL',@ModuloOrigen='QA',@TipoDocumentoOrigen='SALDO_INICIAL',@DocumentoOrigenId=1,@NumeroDocumento='SI',@CantidadEntrada=5,@CostoUnitarioEntrada=40,@IdempotencyKey=@Key;

DECLARE @Resultado TABLE(ReconciliacionInventarioId bigint,Estado varchar(15),Diferencias int);
INSERT @Resultado EXEC inv.usp_ReconciliarInventario @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloId;
IF NOT EXISTS(SELECT 1 FROM @Resultado WHERE Estado='CUADRADO' AND Diferencias=0) THROW 51985,'La reconciliación reportó diferencias inexistentes.',1;

UPDATE inv.SaldoArticuloBodega SET ValorTotal=ValorTotal+1 WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId;
SELECT @OrigenId=OrigenInventarioId FROM inv.SaldoOrigenBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId;
UPDATE inv.SaldoOrigenBodega SET CantidadDisponible=CantidadDisponible+1 WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId AND OrigenInventarioId=@OrigenId;
DELETE FROM @Resultado;
INSERT @Resultado EXEC inv.usp_ReconciliarInventario @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloId;
IF NOT EXISTS(SELECT 1 FROM @Resultado WHERE Estado='DIFERENCIAS' AND Diferencias=2) THROW 51986,'La reconciliación no detectó las alteraciones de saldo y origen.',1;
DECLARE @UltimaId bigint=(SELECT ReconciliacionInventarioId FROM @Resultado);
IF NOT EXISTS(SELECT 1 FROM inv.ReconciliacionInventarioDetalle WHERE EmpresaId=@EmpresaId AND ReconciliacionInventarioId=@UltimaId AND TipoDiferencia='SALDO_KARDEX')
   OR NOT EXISTS(SELECT 1 FROM inv.ReconciliacionInventarioDetalle WHERE EmpresaId=@EmpresaId AND ReconciliacionInventarioId=@UltimaId AND TipoDiferencia='ORIGEN')
    THROW 51987,'El detalle no identifica la naturaleza de cada diferencia.',1;

ROLLBACK TRANSACTION;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA reconciliación correcto: estado cuadrado y detección persistente de diferencias.';
