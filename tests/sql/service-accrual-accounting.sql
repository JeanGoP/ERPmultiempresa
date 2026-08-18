SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
BEGIN TRANSACTION;

DECLARE @Suffix varchar(12)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12);
DECLARE @EmpresaId bigint,@TerceroId bigint,@DocumentoId bigint,@DocumentoLineaId bigint,@CausacionId bigint,@PeriodoId bigint;

INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('CAU-',@Suffix),CONCAT('7',RIGHT(@Suffix,9)),N'Empresa QA Causación'); SET @EmpresaId=SCOPE_IDENTITY();
INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);
INSERT ter.Tercero(EmpresaId,NumeroIdentificacion,RazonSocial,EsProveedor) VALUES(@EmpresaId,CONCAT('4',RIGHT(@Suffix,9)),N'Proveedor servicios',1); SET @TerceroId=SCOPE_IDENTITY();
INSERT core.PeriodoContable(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-08','2026-08-01','2026-08-31'); SET @PeriodoId=SCOPE_IDENTITY();
INSERT cont.CuentaContable(EmpresaId,Codigo,Nombre,Tipo,Naturaleza) VALUES
(@EmpresaId,'513595',N'Servicios','GASTO','D'),
(@EmpresaId,'240810',N'IVA descontable','ACTIVO','D'),
(@EmpresaId,'236525',N'Retención servicios','PASIVO','C'),
(@EmpresaId,'220505',N'Proveedores','PASIVO','C');

INSERT comp.DocumentoProveedor(EmpresaId,TerceroId,TipoDocumento,NumeroDocumento,FechaDocumento,Fuente,Estado,SubtotalBruto,ImpuestoTotal,TotalPagar)
VALUES(@EmpresaId,@TerceroId,'FACTURA',CONCAT('FS-',@Suffix),'2026-08-15','MANUAL','VALIDADO',1000,190,1150); SET @DocumentoId=SCOPE_IDENTITY();
INSERT comp.DocumentoProveedorLinea(EmpresaId,DocumentoProveedorId,NumeroLinea,Descripcion,Clasificacion,Cantidad,PrecioUnitario,SubtotalBruto,Impuesto,TotalNeto)
VALUES(@EmpresaId,@DocumentoId,1,N'Mantenimiento preventivo','SERVICIO_GASTO',1,1000,1000,190,1000); SET @DocumentoLineaId=SCOPE_IDENTITY();
INSERT comp.CausacionServicio(EmpresaId,Numero,DocumentoProveedorId,TerceroId,FechaContable,Estado)
VALUES(@EmpresaId,CONCAT('CAU-',@Suffix),@DocumentoId,@TerceroId,'2026-08-15','VALIDADA'); SET @CausacionId=SCOPE_IDENTITY();
INSERT comp.CausacionServicioLinea(EmpresaId,CausacionServicioId,DocumentoProveedorLineaId,NumeroLinea,Descripcion,CuentaContableCodigo,Base,Impuestos,Retenciones,Total)
VALUES(@EmpresaId,@CausacionId,@DocumentoLineaId,1,N'Mantenimiento preventivo',NULL,1000,190,40,1150);

EXEC comp.usp_AsignarCuentasCausacion @EmpresaId=@EmpresaId,@CausacionServicioId=@CausacionId,@CentroCostoCodigo='TALLER',@ProyectoCodigo='MANT-2026',@LineasJson=N'[{"numeroLinea":1,"cuentaContableCodigo":"513595"}]';
IF NOT EXISTS(SELECT 1 FROM comp.CausacionServicio WHERE EmpresaId=@EmpresaId AND CausacionServicioId=@CausacionId AND Estado='VALIDADA' AND CentroCostoCodigo='TALLER' AND ProyectoCodigo='MANT-2026')
    THROW 51949,'La asignación contable del servicio no quedó validada.',1;

EXEC comp.usp_ContabilizarCausacionServicio @EmpresaId=@EmpresaId,@CausacionServicioId=@CausacionId,@PeriodoContableId=@PeriodoId,
     @CuentaImpuestoCodigo='240810',@CuentaRetencionCodigo='236525',@CuentaPorPagarCodigo='220505';

DECLARE @ComprobanteId bigint=(SELECT ComprobanteContableId FROM comp.CausacionServicio WHERE EmpresaId=@EmpresaId AND CausacionServicioId=@CausacionId);
IF @ComprobanteId IS NULL OR (SELECT Estado FROM comp.CausacionServicio WHERE EmpresaId=@EmpresaId AND CausacionServicioId=@CausacionId)<>'CONTABILIZADA'
    THROW 51950,'La causación no quedó contabilizada.',1;
IF NOT EXISTS(SELECT 1 FROM cont.ComprobanteContable WHERE EmpresaId=@EmpresaId AND ComprobanteContableId=@ComprobanteId AND TotalDebito=1190 AND TotalCredito=1190)
    THROW 51951,'El comprobante no quedó balanceado.',1;
IF (SELECT SUM(Debito) FROM cont.ComprobanteContableLinea WHERE EmpresaId=@EmpresaId AND ComprobanteContableId=@ComprobanteId)<>1190
   OR (SELECT SUM(Credito) FROM cont.ComprobanteContableLinea WHERE EmpresaId=@EmpresaId AND ComprobanteContableId=@ComprobanteId)<>1190
    THROW 51952,'Las líneas débito/crédito no cuadran.',1;
IF EXISTS(SELECT 1 FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId)
    THROW 51953,'Una causación de servicio no debe afectar el Kardex.',1;
IF (SELECT Estado FROM comp.DocumentoProveedor WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoId)<>'CONTABILIZADO'
    THROW 51954,'El documento de proveedor puro servicio no cerró su flujo.',1;

EXEC comp.usp_ContabilizarCausacionServicio @EmpresaId=@EmpresaId,@CausacionServicioId=@CausacionId,@PeriodoContableId=@PeriodoId,
     @CuentaImpuestoCodigo='240810',@CuentaRetencionCodigo='236525',@CuentaPorPagarCodigo='220505';
IF (SELECT COUNT(*) FROM cont.ComprobanteContable WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='CAUSACION_SERVICIO' AND DocumentoOrigenId=@CausacionId)<>1
    THROW 51955,'El reintento duplicó el comprobante.',1;

ROLLBACK TRANSACTION;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA causación correcto: comprobante balanceado, idempotencia y cero movimientos de inventario.';
