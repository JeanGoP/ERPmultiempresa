SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
BEGIN TRANSACTION;

DECLARE @Suffix varchar(12)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12);
DECLARE @EmpresaId bigint,@UnidadId bigint,@ArticuloId bigint,@BodegaId bigint,@PeriodoId bigint,@DocumentoId bigint,@RecepcionId bigint;
DECLARE @ProveedorIdentificacion nvarchar(30)=CONCAT('9',RIGHT(@Suffix,9)),@NumeroFactura nvarchar(50)=CONCAT('FM-',@Suffix),@NumeroRecepcion nvarchar(50)=CONCAT('REC-',@Suffix);
INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('SER-',@Suffix),CONCAT('5',RIGHT(@Suffix,9)),N'Empresa QA Seriales'); SET @EmpresaId=SCOPE_IDENTITY();
INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);
INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES(@EmpresaId,'UND',N'Unidad','und'); SET @UnidadId=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId,ManejaSerial) VALUES(@EmpresaId,'MOTO',N'Motocicleta','INVENTARIO',1,@UnidadId,1); SET @ArticuloId=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'BOD',N'Bodega'); SET @BodegaId=SCOPE_IDENTITY();
INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-08','2026-08-01','2026-08-31'); SET @PeriodoId=SCOPE_IDENTITY();

DECLARE @Lineas nvarchar(max)=CONCAT(N'[{"numeroLinea":1,"articuloId":',@ArticuloId,N',"codigoExterno":"MOTO","descripcion":"Motocicleta","clasificacion":"INVENTARIO","cantidad":2,"unidadMedidaId":',@UnidadId,N',"factorAUnidadBase":1,"precioUnitario":1000,"subtotalBruto":2000,"descuento":0,"impuesto":380,"cargo":0,"totalNeto":2000}]');
DECLARE @Doc TABLE(DocumentoProveedorId bigint,YaExistia bit);
INSERT @Doc EXEC comp.usp_CrearDocumentoProveedor @EmpresaId=@EmpresaId,@ProveedorIdentificacion=@ProveedorIdentificacion,@ProveedorRazonSocial=N'Proveedor motos',@TipoDocumento='FACTURA',@NumeroDocumento=@NumeroFactura,@FechaDocumento='2026-08-15',@Fuente='XML_DIAN',@SubtotalBruto=2000,@DescuentoTotal=0,@ImpuestoTotal=380,@CargoTotal=0,@TotalPagar=2380,@LineasJson=@Lineas;
SELECT @DocumentoId=DocumentoProveedorId FROM @Doc;

DECLARE @Seriales nvarchar(max)=N'[{"numeroLinea":1,"numeroUnidad":1,"motor":"MOT-001","chasis":"CHA-001","vin":"VIN-001","color":"NEGRO","modelo":"2026"},{"numeroLinea":1,"numeroUnidad":2,"motor":"MOT-002","chasis":"CHA-002","vin":"VIN-002","color":"ROJO","modelo":"2026"}]';
EXEC comp.usp_GuardarUnidadesSerializadasDocumento @EmpresaId=@EmpresaId,@DocumentoProveedorId=@DocumentoId,@UnidadesJson=@Seriales;
DECLARE @Preparado TABLE(DocumentoProveedorId bigint,RecepcionMercanciaId bigint NULL,CausacionServicioId bigint NULL,LineasInventario int,LineasServicio int);
INSERT @Preparado EXEC comp.usp_PrepararProcesosDocumento @EmpresaId=@EmpresaId,@DocumentoProveedorId=@DocumentoId,@BodegaId=@BodegaId,@PeriodoInventarioId=@PeriodoId,@FechaContable='2026-08-15',@NumeroRecepcion=@NumeroRecepcion;
SELECT @RecepcionId=RecepcionMercanciaId FROM @Preparado;
EXEC inv.usp_ContabilizarRecepcion @EmpresaId=@EmpresaId,@RecepcionMercanciaId=@RecepcionId;

IF (SELECT COUNT(*) FROM inv.RecepcionMercanciaUnidad u JOIN inv.RecepcionMercanciaLinea l ON l.EmpresaId=u.EmpresaId AND l.RecepcionMercanciaLineaId=u.RecepcionMercanciaLineaId WHERE l.EmpresaId=@EmpresaId AND l.RecepcionMercanciaId=@RecepcionId AND u.UnidadSerializadaId IS NOT NULL)<>2
    THROW 51920,'No se crearon las dos unidades serializadas de la recepción.',1;
IF (SELECT COUNT(*) FROM inv.UnidadIdentificador WHERE EmpresaId=@EmpresaId AND Tipo='MOTOR' AND Valor IN('MOT-001','MOT-002'))<>2
    THROW 51921,'Los motores no quedaron persistidos.',1;
IF (SELECT COUNT(*) FROM inv.UnidadIdentificador WHERE EmpresaId=@EmpresaId AND Tipo='CHASIS' AND Valor IN('CHA-001','CHA-002'))<>2
    THROW 51922,'Los chasis no quedaron persistidos.',1;
IF (SELECT COUNT(*) FROM inv.UnidadIdentificador WHERE EmpresaId=@EmpresaId AND Tipo='VIN' AND Valor IN('VIN-001','VIN-002'))<>2
    THROW 51923,'Los VIN no quedaron persistidos.',1;
IF EXISTS(SELECT 1 FROM inv.UnidadSerializada WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId AND (BodegaActualId<>@BodegaId OR Estado<>'DISPONIBLE'))
    THROW 51924,'La ubicación o estado inicial de las motos es incorrecto.',1;

IF (SELECT COUNT(*) FROM inv.MovimientoInventarioUnidad mu JOIN inv.MovimientoInventario m ON m.EmpresaId=mu.EmpresaId AND m.MovimientoInventarioId=mu.MovimientoInventarioId WHERE m.EmpresaId=@EmpresaId AND m.TipoDocumentoOrigen='RECEPCION_MERCANCIA' AND m.DocumentoOrigenId=@RecepcionId)<>2
    THROW 51925,'Las motos no quedaron vinculadas al movimiento de recepcion.',1;

ROLLBACK TRANSACTION;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA seriales correcto: motor, chasis, VIN, unidad y bodega vinculados a la recepción.';
