SET NOCOUNT ON;
SET XACT_ABORT ON;
EXEC sys.sp_set_session_context @key=N'BypassRls', @value=1;
BEGIN TRANSACTION;

DECLARE @Suffix varchar(12)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12);
DECLARE @EmpresaId bigint;
DECLARE @UnidadId bigint;
DECLARE @ArticuloId bigint;
DECLARE @BodegaId bigint;
DECLARE @PeriodoId bigint;
DECLARE @DocumentoId bigint;

INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('DOC-',@Suffix),CONCAT('6',RIGHT(@Suffix,9)),N'Empresa QA Documento');
SET @EmpresaId=SCOPE_IDENTITY();
INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);
INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES(@EmpresaId,'UND',N'Unidad','und');
SET @UnidadId=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId) VALUES(@EmpresaId,'MOTO-QA',N'Motocicleta QA','INVENTARIO',1,@UnidadId);
SET @ArticuloId=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'BOD',N'Bodega principal');
SET @BodegaId=SCOPE_IDENTITY();
INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-08','2026-08-01','2026-08-31');
SET @PeriodoId=SCOPE_IDENTITY();

DECLARE @Lineas nvarchar(max)=CONCAT(N'[
 {"numeroLinea":1,"articuloId":',@ArticuloId,N',"codigoExterno":"MOTO-QA","descripcion":"Motocicleta QA","clasificacion":"INVENTARIO","cantidad":2,"unidadMedidaId":',@UnidadId,N',"factorAUnidadBase":1,"precioUnitario":1000,"subtotalBruto":2000,"descuento":200,"impuesto":342,"cargo":0,"totalNeto":1800},
 {"numeroLinea":2,"articuloId":null,"codigoExterno":"SERV-QA","descripcion":"Servicio de mantenimiento","clasificacion":"SERVICIO_GASTO","cantidad":1,"unidadMedidaId":null,"factorAUnidadBase":1,"precioUnitario":300,"subtotalBruto":300,"descuento":0,"impuesto":57,"cargo":0,"totalNeto":300}
]');

DECLARE @Resultado TABLE(DocumentoProveedorId bigint,YaExistia bit);
INSERT @Resultado EXEC comp.usp_CrearDocumentoProveedor
    @EmpresaId=@EmpresaId,@ProveedorIdentificacion=N'900777001',@ProveedorRazonSocial=N'Proveedor QA SAS',
    @TipoDocumento='FACTURA',@NumeroDocumento=N'FE-QA-1',@FechaDocumento='2026-08-15',@FechaVencimiento='2026-09-15',
    @CufeCude=N'CUFE-QA-DOCUMENTO-UNICO',@Fuente='XML_DIAN',@SubtotalBruto=2300,@DescuentoTotal=200,
    @ImpuestoTotal=399,@CargoTotal=0,@TotalPagar=2499,@LineasJson=@Lineas;
SELECT @DocumentoId=DocumentoProveedorId FROM @Resultado;

DELETE FROM @Resultado;
INSERT @Resultado EXEC comp.usp_CrearDocumentoProveedor
    @EmpresaId=@EmpresaId,@ProveedorIdentificacion=N'900777001',@ProveedorRazonSocial=N'Proveedor QA SAS',
    @TipoDocumento='FACTURA',@NumeroDocumento=N'FE-QA-1',@FechaDocumento='2026-08-15',@FechaVencimiento='2026-09-15',
    @CufeCude=N'CUFE-QA-DOCUMENTO-UNICO',@Fuente='XML_DIAN',@SubtotalBruto=2300,@DescuentoTotal=200,
    @ImpuestoTotal=399,@CargoTotal=0,@TotalPagar=2499,@LineasJson=@Lineas;

IF NOT EXISTS(SELECT 1 FROM @Resultado WHERE DocumentoProveedorId=@DocumentoId AND YaExistia=1)
    THROW 51920,'La idempotencia del documento de proveedor falló.',1;
IF (SELECT COUNT(*) FROM comp.DocumentoProveedorLinea WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoId)<>2
    THROW 51921,'No se guardaron correctamente las líneas mixtas.',1;

DECLARE @Procesos TABLE(DocumentoProveedorId bigint,RecepcionMercanciaId bigint,CausacionServicioId bigint,LineasInventario int,LineasServicio int);
INSERT @Procesos EXEC comp.usp_PrepararProcesosDocumento
    @EmpresaId=@EmpresaId,@DocumentoProveedorId=@DocumentoId,@BodegaId=@BodegaId,@PeriodoInventarioId=@PeriodoId,
    @FechaContable='2026-08-15',@NumeroRecepcion=N'REC-QA-1',@NumeroCausacion=N'CAU-QA-1';

IF NOT EXISTS(SELECT 1 FROM @Procesos WHERE RecepcionMercanciaId IS NOT NULL AND CausacionServicioId IS NOT NULL AND LineasInventario=1 AND LineasServicio=1)
    THROW 51922,'La factura mixta no se separó en recepción y causación.',1;
IF (SELECT COUNT(*) FROM inv.RecepcionMercanciaLinea WHERE EmpresaId=@EmpresaId)<>1
    THROW 51923,'La recepción contiene líneas incorrectas.',1;
IF (SELECT COUNT(*) FROM comp.CausacionServicioLinea WHERE EmpresaId=@EmpresaId)<>1
    THROW 51924,'La causación contiene líneas incorrectas.',1;
IF EXISTS(SELECT 1 FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId)
    THROW 51925,'Preparar un documento no debe afectar el Kardex.',1;

ROLLBACK TRANSACTION;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA documento correcto: persistencia idempotente, factura mixta y separación sin afectar Kardex.';
