SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
BEGIN TRANSACTION;

DECLARE @Suffix varchar(12)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12),@Key uniqueidentifier=NEWID();
DECLARE @EmpresaId bigint,@UnidadId bigint,@ArticuloId bigint,@BodegaId bigint,@PeriodoId bigint;
INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('CIE-',@Suffix),CONCAT('8',RIGHT(@Suffix,9)),N'Empresa QA Cierre'); SET @EmpresaId=SCOPE_IDENTITY();
INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);
INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES(@EmpresaId,'UND',N'Unidad','und'); SET @UnidadId=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId) VALUES(@EmpresaId,'A',N'Artículo','INVENTARIO',1,@UnidadId); SET @ArticuloId=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'BOD',N'Bodega'); SET @BodegaId=SCOPE_IDENTITY();
INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-08','2026-08-01','2026-08-31'); SET @PeriodoId=SCOPE_IDENTITY();
EXEC inv.usp_ContabilizarEntrada @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoId,@FechaMovimiento='2026-08-10',@FechaContable='2026-08-10',@TipoMovimiento='SALDO_INICIAL',@ModuloOrigen='QA',@TipoDocumentoOrigen='SALDO_INICIAL',@DocumentoOrigenId=1,@NumeroDocumento='SI',@CantidadEntrada=5,@CostoUnitarioEntrada=75,@IdempotencyKey=@Key;
EXEC inv.usp_RegistrarDeterioroInventario @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoId,@Tipo='DETERIORO',@ValorNetoRealizable=350,@Motivo=N'Prueba de deterioro previo al cierre';

EXEC inv.usp_CerrarPeriodoInventario @EmpresaId=@EmpresaId,@PeriodoInventarioId=@PeriodoId;
IF (SELECT Estado FROM core.PeriodoInventario WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoId)<>'CERRADO' THROW 51995,'El periodo no quedó cerrado.',1;
IF NOT EXISTS(SELECT 1 FROM inv.CierrePeriodoInventario WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoId AND VersionCierre=1 AND TotalReferencias=1 AND TotalExistencia=5 AND TotalValor=375 AND Estado='VIGENTE') THROW 51996,'El resumen de cierre es incorrecto.',1;
IF NOT EXISTS(SELECT 1 FROM inv.CierrePeriodoInventarioSaldo s JOIN inv.CierrePeriodoInventario c ON c.EmpresaId=s.EmpresaId AND c.CierrePeriodoInventarioId=s.CierrePeriodoInventarioId WHERE s.EmpresaId=@EmpresaId AND c.PeriodoInventarioId=@PeriodoId AND s.Existencia=5 AND s.CostoPromedio=75 AND s.ValorTotal=375 AND s.DeterioroAcumulado=25 AND s.ValorNetoContable=350) THROW 51997,'La fotografía de costo histórico, deterioro y valor neto es incorrecta.',1;

EXEC inv.usp_ReabrirPeriodoInventario @EmpresaId=@EmpresaId,@PeriodoInventarioId=@PeriodoId,@Motivo=N'Ajuste autorizado por auditoría';
IF (SELECT Estado FROM core.PeriodoInventario WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoId)<>'REABIERTO' THROW 51998,'El periodo no quedó reabierto.',1;
IF NOT EXISTS(SELECT 1 FROM inv.CierrePeriodoInventario WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoId AND VersionCierre=1 AND Estado='REABIERTO') THROW 51999,'La versión de cierre no conservó la trazabilidad de reapertura.',1;

ROLLBACK TRANSACTION;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA cierre correcto: validación, fotografía versionada y reapertura auditada.';
