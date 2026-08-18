SET NOCOUNT ON;
SET XACT_ABORT ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
BEGIN TRANSACTION;

DECLARE @Suffix varchar(12)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12);
DECLARE @EmpresaId bigint,@UnidadId bigint,@ArticuloId bigint,@MotoArticuloId bigint,@BodegaId bigint,@PeriodoId bigint,
        @EntradaId bigint,@SalidaId bigint,@ReversaSalidaId bigint,@ReversaEntradaId bigint,
        @DocumentoId bigint,@RecepcionId bigint,@RecepcionLineaId bigint,@MovimientoRecepcionId bigint,@MotoId bigint,@ReversaMotoId bigint;
INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('REV-',@Suffix),CONCAT('6',RIGHT(@Suffix,9)),N'Empresa QA reversas'); SET @EmpresaId=SCOPE_IDENTITY();
INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);
INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES(@EmpresaId,'UND',N'Unidad','und'); SET @UnidadId=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId) VALUES(@EmpresaId,'ART',N'Articulo reversible','INVENTARIO',1,@UnidadId); SET @ArticuloId=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId,ManejaSerial) VALUES(@EmpresaId,'MOTO',N'Moto reversible','INVENTARIO',1,@UnidadId,1); SET @MotoArticuloId=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'BOD',N'Bodega'); SET @BodegaId=SCOPE_IDENTITY();
INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-08','2026-08-01','2026-08-31'); SET @PeriodoId=SCOPE_IDENTITY();

DECLARE @R TABLE(MovimientoInventarioId bigint,ExistenciaPosterior decimal(20,6),CostoPromedioPosterior decimal(20,8),ValorTotalPosterior decimal(20,4),YaExistia bit);
INSERT @R EXEC inv.usp_ContabilizarEntrada @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoId,
    @FechaMovimiento='2026-08-01',@FechaContable='2026-08-01',@TipoMovimiento='COMPRA',@ModuloOrigen='QA',@TipoDocumentoOrigen='COMPRA_DIRECTA',
    @DocumentoOrigenId=1,@NumeroDocumento=N'C-1',@CantidadEntrada=10,@CostoUnitarioEntrada=100,@IdempotencyKey='31313131-1111-1111-1111-111111111111';
SELECT @EntradaId=MovimientoInventarioId FROM @R; DELETE FROM @R;
INSERT @R EXEC inv.usp_ContabilizarSalida @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoId,
    @FechaMovimiento='2026-08-02',@FechaContable='2026-08-02',@TipoMovimiento='VENTA',@ModuloOrigen='QA',@TipoDocumentoOrigen='VENTA_DIRECTA',
    @DocumentoOrigenId=2,@NumeroDocumento=N'V-1',@CantidadSalida=3,@IdempotencyKey='31313131-2222-2222-2222-222222222222';
SELECT @SalidaId=MovimientoInventarioId FROM @R;

EXEC inv.usp_ReversarMovimientoInventario @EmpresaId=@EmpresaId,@MovimientoOriginalId=@SalidaId,@PeriodoInventarioId=@PeriodoId,
    @FechaContable='2026-08-03',@Motivo=N'Anulacion autorizada de venta de prueba',@IdempotencyKey='31313131-3333-3333-3333-333333333333';
SELECT @ReversaSalidaId=MovimientoReversionId FROM inv.ReversionMovimientoInventario WHERE EmpresaId=@EmpresaId AND IdempotencyKey='31313131-3333-3333-3333-333333333333';
IF NOT EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId AND Existencia=10 AND ValorTotal=1000)
    THROW 51978,'La reversa de salida no restauro cantidad y valor.',1;
IF NOT EXISTS(SELECT 1 FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND MovimientoInventarioId=@ReversaSalidaId AND MovimientoRelacionadoId=@SalidaId AND TipoMovimiento='REVERSA_SALIDA')
    THROW 51979,'La reversa de salida no quedo relacionada con el movimiento original.',1;

EXEC inv.usp_ReversarMovimientoInventario @EmpresaId=@EmpresaId,@MovimientoOriginalId=@EntradaId,@PeriodoInventarioId=@PeriodoId,
    @FechaContable='2026-08-04',@Motivo=N'Anulacion autorizada de compra de prueba',@IdempotencyKey='31313131-4444-4444-4444-444444444444';
SELECT @ReversaEntradaId=MovimientoReversionId FROM inv.ReversionMovimientoInventario WHERE EmpresaId=@EmpresaId AND IdempotencyKey='31313131-4444-4444-4444-444444444444';
IF NOT EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId AND Existencia=0 AND ValorTotal=0)
    THROW 51980,'La reversa de entrada no retiro cantidad y valor.',1;
IF EXISTS(SELECT 1 FROM inv.SaldoOrigenBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId AND CantidadDisponible<>0)
    THROW 51981,'La reversa de entrada no retiro el origen exacto.',1;
EXEC inv.usp_ReversarMovimientoInventario @EmpresaId=@EmpresaId,@MovimientoOriginalId=@EntradaId,@PeriodoInventarioId=@PeriodoId,
    @FechaContable='2026-08-04',@Motivo=N'Anulacion autorizada de compra de prueba',@IdempotencyKey='31313131-4444-4444-4444-444444444444';
IF (SELECT COUNT(*) FROM inv.ReversionMovimientoInventario WHERE EmpresaId=@EmpresaId AND MovimientoOriginalId=@EntradaId AND MovimientoReversionId=@ReversaEntradaId)<>1
    THROW 51982,'El reintento de la reversa no fue idempotente.',1;

DECLARE @ProveedorIdentificacion nvarchar(30)=CONCAT('9',RIGHT(@Suffix,9)),@NumeroFactura nvarchar(50)=CONCAT('FM-',@Suffix),@NumeroRecepcion nvarchar(50)=CONCAT('RM-',@Suffix);
DECLARE @Lineas nvarchar(max)=CONCAT(N'[{"numeroLinea":1,"articuloId":',@MotoArticuloId,N',"codigoExterno":"MOTO","descripcion":"Moto","clasificacion":"INVENTARIO","cantidad":1,"unidadMedidaId":',@UnidadId,N',"factorAUnidadBase":1,"precioUnitario":5000,"subtotalBruto":5000,"descuento":0,"impuesto":950,"cargo":0,"totalNeto":5000}]');
DECLARE @Doc TABLE(DocumentoProveedorId bigint,YaExistia bit);
INSERT @Doc EXEC comp.usp_CrearDocumentoProveedor @EmpresaId=@EmpresaId,@ProveedorIdentificacion=@ProveedorIdentificacion,@ProveedorRazonSocial=N'Proveedor moto',@TipoDocumento='FACTURA',@NumeroDocumento=@NumeroFactura,@FechaDocumento='2026-08-05',@Fuente='XML_DIAN',@SubtotalBruto=5000,@DescuentoTotal=0,@ImpuestoTotal=950,@CargoTotal=0,@TotalPagar=5950,@LineasJson=@Lineas;
SELECT @DocumentoId=DocumentoProveedorId FROM @Doc;
EXEC comp.usp_GuardarUnidadesSerializadasDocumento @EmpresaId=@EmpresaId,@DocumentoProveedorId=@DocumentoId,@UnidadesJson=N'[{"numeroLinea":1,"numeroUnidad":1,"motor":"MOT-REV-1","chasis":"CHA-REV-1","vin":"VIN-REV-1"}]';
DECLARE @Prep TABLE(DocumentoProveedorId bigint,RecepcionMercanciaId bigint NULL,CausacionServicioId bigint NULL,LineasInventario int,LineasServicio int);
INSERT @Prep EXEC comp.usp_PrepararProcesosDocumento @EmpresaId=@EmpresaId,@DocumentoProveedorId=@DocumentoId,@BodegaId=@BodegaId,@PeriodoInventarioId=@PeriodoId,@FechaContable='2026-08-05',@NumeroRecepcion=@NumeroRecepcion;
SELECT @RecepcionId=RecepcionMercanciaId FROM @Prep;
EXEC inv.usp_ContabilizarRecepcion @EmpresaId=@EmpresaId,@RecepcionMercanciaId=@RecepcionId;
SELECT @RecepcionLineaId=RecepcionMercanciaLineaId FROM inv.RecepcionMercanciaLinea WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionId;
SELECT @MotoId=UnidadSerializadaId FROM inv.RecepcionMercanciaUnidad WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaLineaId=@RecepcionLineaId;
SELECT @MovimientoRecepcionId=MovimientoInventarioId FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND TipoDocumentoOrigen='RECEPCION_MERCANCIA' AND DocumentoOrigenId=@RecepcionId;
EXEC inv.usp_ReversarMovimientoInventario @EmpresaId=@EmpresaId,@MovimientoOriginalId=@MovimientoRecepcionId,@PeriodoInventarioId=@PeriodoId,
    @FechaContable='2026-08-06',@Motivo=N'Anulacion autorizada de recepcion serial',@IdempotencyKey='31313131-5555-5555-5555-555555555555';
SELECT @ReversaMotoId=MovimientoReversionId FROM inv.ReversionMovimientoInventario WHERE EmpresaId=@EmpresaId AND IdempotencyKey='31313131-5555-5555-5555-555555555555';
IF NOT EXISTS(SELECT 1 FROM inv.UnidadSerializada WHERE EmpresaId=@EmpresaId AND UnidadSerializadaId=@MotoId AND Estado='BAJA' AND BodegaActualId IS NULL)
    THROW 51983,'La unidad serializada no quedo dada de baja al reversar su recepcion.',1;
IF NOT EXISTS(SELECT 1 FROM inv.MovimientoInventarioUnidad WHERE EmpresaId=@EmpresaId AND MovimientoInventarioId=@ReversaMotoId AND UnidadSerializadaId=@MotoId AND EstadoPosterior='BAJA')
    THROW 51984,'La reversa serial no quedo registrada en la bitacora de la unidad.',1;

ROLLBACK;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA reversas correcto: movimientos contrarios, costo, origen, seriales, relacion e idempotencia.';
