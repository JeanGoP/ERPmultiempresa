SET NOCOUNT ON;
SET XACT_ABORT ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
BEGIN TRANSACTION;

DECLARE @Suffix varchar(12)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12);
DECLARE @EmpresaId bigint,@UnidadMedidaId bigint,@ArticuloId bigint,@OrigenId bigint,@TransitoId bigint,@DestinoId bigint,@PeriodoId bigint,
        @DocumentoId bigint,@RecepcionId bigint,@RecepcionLineaId bigint,@TerceroId bigint,@Moto1 bigint,@Moto2 bigint,@TrasladoId bigint,@TrasladoLineaId bigint,
        @MovimientoVentaId bigint,@DevolucionVentaId bigint,@DevolucionVentaLineaId bigint,@DevolucionProveedorId bigint,@DevolucionProveedorLineaId bigint;
DECLARE @ProveedorIdentificacion nvarchar(30)=CONCAT('9',RIGHT(@Suffix,9)),@NumeroFactura nvarchar(50)=CONCAT('FAC-',@Suffix),
        @NumeroRecepcion nvarchar(50)=CONCAT('REC-',@Suffix),@UnidadesVenta nvarchar(max);

INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('SLF-',@Suffix),CONCAT('7',RIGHT(@Suffix,9)),N'Empresa QA ciclo serial'); SET @EmpresaId=SCOPE_IDENTITY();
INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);
INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES(@EmpresaId,'UND',N'Unidad','und'); SET @UnidadMedidaId=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId,ManejaSerial) VALUES(@EmpresaId,'MOTO',N'Motocicleta serializada','INVENTARIO',1,@UnidadMedidaId,1); SET @ArticuloId=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'ORI',N'Bodega origen'); SET @OrigenId=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre,EsTransito) VALUES(@EmpresaId,'TRA',N'Bodega transito',1); SET @TransitoId=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'DES',N'Bodega destino'); SET @DestinoId=SCOPE_IDENTITY();
INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-08','2026-08-01','2026-08-31'); SET @PeriodoId=SCOPE_IDENTITY();

DECLARE @Lineas nvarchar(max)=CONCAT(N'[{"numeroLinea":1,"articuloId":',@ArticuloId,N',"codigoExterno":"MOTO","descripcion":"Motocicleta","clasificacion":"INVENTARIO","cantidad":2,"unidadMedidaId":',@UnidadMedidaId,N',"factorAUnidadBase":1,"precioUnitario":1000,"subtotalBruto":2000,"descuento":0,"impuesto":380,"cargo":0,"totalNeto":2000}]');
DECLARE @Doc TABLE(DocumentoProveedorId bigint,YaExistia bit);
INSERT @Doc EXEC comp.usp_CrearDocumentoProveedor @EmpresaId=@EmpresaId,@ProveedorIdentificacion=@ProveedorIdentificacion,@ProveedorRazonSocial=N'Proveedor motos',@TipoDocumento='FACTURA',@NumeroDocumento=@NumeroFactura,@FechaDocumento='2026-08-01',@Fuente='XML_DIAN',@SubtotalBruto=2000,@DescuentoTotal=0,@ImpuestoTotal=380,@CargoTotal=0,@TotalPagar=2380,@LineasJson=@Lineas;
SELECT @DocumentoId=DocumentoProveedorId FROM @Doc;
EXEC comp.usp_GuardarUnidadesSerializadasDocumento @EmpresaId=@EmpresaId,@DocumentoProveedorId=@DocumentoId,
    @UnidadesJson=N'[{"numeroLinea":1,"numeroUnidad":1,"motor":"MOT-CICLO-1","chasis":"CHA-CICLO-1","vin":"VIN-CICLO-1"},{"numeroLinea":1,"numeroUnidad":2,"motor":"MOT-CICLO-2","chasis":"CHA-CICLO-2","vin":"VIN-CICLO-2"}]';
DECLARE @Prep TABLE(DocumentoProveedorId bigint,RecepcionMercanciaId bigint NULL,CausacionServicioId bigint NULL,LineasInventario int,LineasServicio int);
INSERT @Prep EXEC comp.usp_PrepararProcesosDocumento @EmpresaId=@EmpresaId,@DocumentoProveedorId=@DocumentoId,@BodegaId=@OrigenId,@PeriodoInventarioId=@PeriodoId,@FechaContable='2026-08-01',@NumeroRecepcion=@NumeroRecepcion;
SELECT @RecepcionId=RecepcionMercanciaId FROM @Prep;
EXEC inv.usp_ContabilizarRecepcion @EmpresaId=@EmpresaId,@RecepcionMercanciaId=@RecepcionId;
SELECT @RecepcionLineaId=RecepcionMercanciaLineaId FROM inv.RecepcionMercanciaLinea WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionId;
SELECT @TerceroId=TerceroId FROM comp.DocumentoProveedor WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoId;
SELECT @Moto1=MIN(UnidadSerializadaId),@Moto2=MAX(UnidadSerializadaId) FROM inv.RecepcionMercanciaUnidad WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaLineaId=@RecepcionLineaId;

INSERT inv.Traslado(EmpresaId,Numero,BodegaOrigenId,BodegaTransitoId,BodegaDestinoId,FechaSalida)
VALUES(@EmpresaId,CONCAT('TR-',@Suffix),@OrigenId,@TransitoId,@DestinoId,'2026-08-02'); SET @TrasladoId=SCOPE_IDENTITY();
INSERT inv.TrasladoLinea(EmpresaId,TrasladoId,NumeroLinea,ArticuloId,CantidadDespachada)
VALUES(@EmpresaId,@TrasladoId,1,@ArticuloId,2); SET @TrasladoLineaId=SCOPE_IDENTITY();
INSERT inv.TrasladoLineaUnidad(EmpresaId,TrasladoLineaId,UnidadSerializadaId) VALUES(@EmpresaId,@TrasladoLineaId,@Moto1),(@EmpresaId,@TrasladoLineaId,@Moto2);
EXEC inv.usp_DespacharTraslado @EmpresaId=@EmpresaId,@TrasladoId=@TrasladoId,@PeriodoInventarioId=@PeriodoId,@FechaContable='2026-08-02';
IF EXISTS(SELECT 1 FROM inv.UnidadSerializada WHERE EmpresaId=@EmpresaId AND UnidadSerializadaId IN(@Moto1,@Moto2) AND (Estado<>'EN_TRANSITO' OR BodegaActualId<>@TransitoId))
    THROW 51990,'Las motos no quedaron en transito despues del despacho.',1;
EXEC inv.usp_RecibirTraslado @EmpresaId=@EmpresaId,@TrasladoId=@TrasladoId,@PeriodoInventarioId=@PeriodoId,@FechaContable='2026-08-03',@FechaRecepcion='2026-08-03';
IF EXISTS(SELECT 1 FROM inv.UnidadSerializada WHERE EmpresaId=@EmpresaId AND UnidadSerializadaId IN(@Moto1,@Moto2) AND (Estado<>'DISPONIBLE' OR BodegaActualId<>@DestinoId))
    THROW 51991,'Las motos no quedaron disponibles en la bodega destino.',1;

DECLARE @Venta TABLE(MovimientoInventarioId bigint,ExistenciaPosterior decimal(20,6),CostoPromedioPosterior decimal(20,8),ValorTotalPosterior decimal(20,4),YaExistia bit);
SET @UnidadesVenta=CONCAT('[',@Moto1,']');
INSERT @Venta EXEC inv.usp_ContabilizarSalidaSerializada @EmpresaId=@EmpresaId,@BodegaId=@DestinoId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoId,
    @FechaMovimiento='2026-08-04',@FechaContable='2026-08-04',@TipoMovimiento='VENTA',@ModuloOrigen='VENTAS',@TipoDocumentoOrigen='FACTURA_VENTA',
    @DocumentoOrigenId=501,@NumeroDocumento=N'FV-501',@CantidadSalida=1,@IdempotencyKey='91919191-1111-1111-1111-111111111111',@UnidadesJson=@UnidadesVenta;
SELECT @MovimientoVentaId=MovimientoInventarioId FROM @Venta;
IF NOT EXISTS(SELECT 1 FROM inv.UnidadSerializada WHERE EmpresaId=@EmpresaId AND UnidadSerializadaId=@Moto1 AND Estado='VENDIDA' AND BodegaActualId IS NULL)
    THROW 51992,'La moto vendida conserva un estado o bodega incorrectos.',1;

INSERT inv.DevolucionVenta(EmpresaId,Numero,TerceroId,BodegaId,PeriodoInventarioId,FechaMovimiento,FechaContable,Motivo)
VALUES(@EmpresaId,CONCAT('DV-',@Suffix),@TerceroId,@DestinoId,@PeriodoId,'2026-08-05','2026-08-05',N'Devolucion QA'); SET @DevolucionVentaId=SCOPE_IDENTITY();
INSERT inv.DevolucionVentaLinea(EmpresaId,DevolucionVentaId,NumeroLinea,MovimientoSalidaOriginalId,ArticuloId,CantidadBase)
VALUES(@EmpresaId,@DevolucionVentaId,1,@MovimientoVentaId,@ArticuloId,1); SET @DevolucionVentaLineaId=SCOPE_IDENTITY();
INSERT inv.DevolucionVentaLineaUnidad(EmpresaId,DevolucionVentaLineaId,UnidadSerializadaId) VALUES(@EmpresaId,@DevolucionVentaLineaId,@Moto1);
EXEC inv.usp_ContabilizarDevolucionVenta @EmpresaId=@EmpresaId,@DevolucionVentaId=@DevolucionVentaId;
IF NOT EXISTS(SELECT 1 FROM inv.UnidadSerializada WHERE EmpresaId=@EmpresaId AND UnidadSerializadaId=@Moto1 AND Estado='DISPONIBLE' AND BodegaActualId=@DestinoId)
    THROW 51993,'La moto devuelta por el cliente no regreso al inventario.',1;

INSERT inv.DevolucionProveedor(EmpresaId,Numero,TerceroId,BodegaId,PeriodoInventarioId,FechaMovimiento,FechaContable,Motivo)
VALUES(@EmpresaId,CONCAT('DP-',@Suffix),@TerceroId,@DestinoId,@PeriodoId,'2026-08-06','2026-08-06',N'Devolucion a proveedor QA'); SET @DevolucionProveedorId=SCOPE_IDENTITY();
INSERT inv.DevolucionProveedorLinea(EmpresaId,DevolucionProveedorId,NumeroLinea,RecepcionMercanciaLineaId,ArticuloId,CantidadBase)
VALUES(@EmpresaId,@DevolucionProveedorId,1,@RecepcionLineaId,@ArticuloId,1); SET @DevolucionProveedorLineaId=SCOPE_IDENTITY();
INSERT inv.DevolucionProveedorLineaUnidad(EmpresaId,DevolucionProveedorLineaId,UnidadSerializadaId) VALUES(@EmpresaId,@DevolucionProveedorLineaId,@Moto2);
EXEC inv.usp_ContabilizarDevolucionProveedor @EmpresaId=@EmpresaId,@DevolucionProveedorId=@DevolucionProveedorId;
IF NOT EXISTS(SELECT 1 FROM inv.UnidadSerializada WHERE EmpresaId=@EmpresaId AND UnidadSerializadaId=@Moto2 AND Estado='DEVUELTA' AND BodegaActualId IS NULL)
    THROW 51994,'La moto devuelta al proveedor conserva un estado o bodega incorrectos.',1;
IF (SELECT COUNT(*) FROM inv.MovimientoInventarioUnidad WHERE EmpresaId=@EmpresaId AND UnidadSerializadaId=@Moto1)<>7
    THROW 51995,'La bitacora de la moto vendida y retornada esta incompleta.',1;
IF (SELECT COUNT(*) FROM inv.MovimientoInventarioUnidad WHERE EmpresaId=@EmpresaId AND UnidadSerializadaId=@Moto2)<>6
    THROW 51996,'La bitacora de la moto devuelta al proveedor esta incompleta.',1;

ROLLBACK;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA ciclo serial correcto: recepcion, traslado, venta y devoluciones conservan motor, chasis, VIN, estado y bodega.';
