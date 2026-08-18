SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
BEGIN TRANSACTION;

DECLARE @Suffix varchar(12)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12);
DECLARE @EmpresaId bigint,@UnidadId bigint,@ArticuloA bigint,@ArticuloB bigint,@BodegaId bigint,@PeriodoId bigint,@ConteoId bigint;
DECLARE @LineaA bigint,@LineaB bigint,@Usuario1 bigint,@Usuario2 bigint;
DECLARE @KeyA uniqueidentifier=NEWID(),@KeyB uniqueidentifier=NEWID();
INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('CNT-',@Suffix),CONCAT('1',RIGHT(@Suffix,9)),N'Empresa QA Conteo'); SET @EmpresaId=SCOPE_IDENTITY();
INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);
INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES(@EmpresaId,'UND',N'Unidad','und'); SET @UnidadId=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId) VALUES(@EmpresaId,'A',N'Artículo con faltante','INVENTARIO',1,@UnidadId); SET @ArticuloA=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId) VALUES(@EmpresaId,'B',N'Artículo con sobrante','INVENTARIO',1,@UnidadId); SET @ArticuloB=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'BOD',N'Bodega'); SET @BodegaId=SCOPE_IDENTITY();
INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-08','2026-08-01','2026-08-31'); SET @PeriodoId=SCOPE_IDENTITY();
INSERT seg.Usuario(Correo,NombreCompleto) VALUES(CONCAT('c1-',@Suffix,'@qa.local'),N'Contador uno'); SET @Usuario1=SCOPE_IDENTITY();
INSERT seg.Usuario(Correo,NombreCompleto) VALUES(CONCAT('c2-',@Suffix,'@qa.local'),N'Contador dos'); SET @Usuario2=SCOPE_IDENTITY();
EXEC inv.usp_ContabilizarEntrada @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloA,@PeriodoInventarioId=@PeriodoId,@FechaMovimiento='2026-08-10',@FechaContable='2026-08-10',@TipoMovimiento='SALDO_INICIAL',@ModuloOrigen='QA',@TipoDocumentoOrigen='SALDO_INICIAL',@DocumentoOrigenId=1,@NumeroDocumento='SI-A',@CantidadEntrada=10,@CostoUnitarioEntrada=100,@IdempotencyKey=@KeyA;
EXEC inv.usp_ContabilizarEntrada @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloB,@PeriodoInventarioId=@PeriodoId,@FechaMovimiento='2026-08-10',@FechaContable='2026-08-10',@TipoMovimiento='SALDO_INICIAL',@ModuloOrigen='QA',@TipoDocumentoOrigen='SALDO_INICIAL',@DocumentoOrigenId=2,@NumeroDocumento='SI-B',@CantidadEntrada=5,@CostoUnitarioEntrada=50,@IdempotencyKey=@KeyB;

INSERT inv.ConteoFisico(EmpresaId,Numero,BodegaId,FechaCorte,Estado) VALUES(@EmpresaId,CONCAT('CNT-',@Suffix),@BodegaId,'2026-08-20','PREPARACION'); SET @ConteoId=SCOPE_IDENTITY();
EXEC inv.usp_IniciarConteoFisico @EmpresaId=@EmpresaId,@ConteoFisicoId=@ConteoId,@UsuarioId=@Usuario1;
SELECT @LineaA=ConteoFisicoLineaId FROM inv.ConteoFisicoLinea WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoId AND ArticuloId=@ArticuloA;
SELECT @LineaB=ConteoFisicoLineaId FROM inv.ConteoFisicoLinea WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoId AND ArticuloId=@ArticuloB;
INSERT inv.ConteoCaptura(EmpresaId,ConteoFisicoLineaId,NumeroConteo,CantidadContada,UsuarioId) VALUES
(@EmpresaId,@LineaA,1,8,@Usuario1),(@EmpresaId,@LineaA,2,8,@Usuario2),(@EmpresaId,@LineaB,1,7,@Usuario1),(@EmpresaId,@LineaB,2,7,@Usuario2);
EXEC inv.usp_EnviarConteoRevision @EmpresaId=@EmpresaId,@ConteoFisicoId=@ConteoId,@UsuarioId=@Usuario1;
DECLARE @Aprobaciones nvarchar(max)=CONCAT(N'[{"conteoFisicoLineaId":',@LineaA,N',"cantidadAprobada":8},{"conteoFisicoLineaId":',@LineaB,N',"cantidadAprobada":7}]');
EXEC inv.usp_AprobarConteoFisico @EmpresaId=@EmpresaId,@ConteoFisicoId=@ConteoId,@AprobacionesJson=@Aprobaciones,@UsuarioId=@Usuario2;
EXEC inv.usp_AplicarConteoFisico @EmpresaId=@EmpresaId,@ConteoFisicoId=@ConteoId,@PeriodoInventarioId=@PeriodoId,@FechaContable='2026-08-20';

IF NOT EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloA AND Existencia=8 AND ValorTotal=800)
    THROW 51980,'El faltante del conteo no se aplicó correctamente.',1;
IF NOT EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloB AND Existencia=7 AND ValorTotal=350)
    THROW 51981,'El sobrante del conteo no se aplicó correctamente.',1;
IF (SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='CONTEO_FISICO' AND DocumentoOrigenId=@ConteoId)<>2
    THROW 51982,'El conteo no generó los dos ajustes esperados.',1;
IF EXISTS(SELECT 1 FROM inv.ConteoFisicoLinea WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoId AND DiferenciaAprobada IS NULL)
    THROW 51983,'Las diferencias aprobadas no quedaron registradas.',1;
IF EXISTS(SELECT 1 FROM inv.BloqueoConteoFisico WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoId AND Activo=1)
    THROW 51985,'Los bloqueos del conteo no se liberaron al aplicar.',1;

EXEC inv.usp_AplicarConteoFisico @EmpresaId=@EmpresaId,@ConteoFisicoId=@ConteoId,@PeriodoInventarioId=@PeriodoId,@FechaContable='2026-08-20';
IF (SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='CONTEO_FISICO' AND DocumentoOrigenId=@ConteoId)<>2
    THROW 51984,'El reintento duplicó los ajustes de conteo.',1;

ROLLBACK TRANSACTION;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA conteo correcto: faltantes, sobrantes, costo e idempotencia.';
