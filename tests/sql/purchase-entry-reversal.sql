SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
GO
CREATE PROCEDURE #SeedPurchaseReversal
    @EmpresaId bigint OUTPUT,@ArticuloId bigint OUTPUT,@BodegaId bigint OUTPUT,@PeriodoId bigint OUTPUT,
    @DocumentoId bigint OUTPUT,@RecepcionId bigint OUTPUT,@UnidadId bigint OUTPUT,@Suffix varchar(12) OUTPUT,@Serial bit=1
AS
BEGIN
    SET NOCOUNT ON;
    SET @Suffix=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12);
    INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('PR-',@Suffix),CONCAT('7',RIGHT(@Suffix,9)),N'Compra reversible QA');
    SET @EmpresaId=SCOPE_IDENTITY();
    INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);
    INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES(@EmpresaId,'UND',N'Unidad','und');
    DECLARE @Medida bigint=SCOPE_IDENTITY();
    INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId,ManejaSerial)
    VALUES(@EmpresaId,'MOTO',N'Moto reversible','INVENTARIO',1,@Medida,@Serial);
    SET @ArticuloId=SCOPE_IDENTITY();
    INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'ORI',N'Bodega origen');
    SET @BodegaId=SCOPE_IDENTITY();
    INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-11','2026-11-01','2026-11-30');
    SET @PeriodoId=SCOPE_IDENTITY();
    INSERT core.PeriodoContable(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-11','2026-11-01','2026-11-30');
    DECLARE @Lineas nvarchar(max)=CONCAT(N'[{"numeroLinea":1,"articuloId":',@ArticuloId,
        N',"codigoExterno":"MOTO","descripcion":"Moto","clasificacion":"INVENTARIO","cantidad":1,"unidadMedidaId":',@Medida,
        N',"factorAUnidadBase":1,"precioUnitario":5000,"subtotalBruto":5000,"descuento":0,"impuesto":950,"cargo":0,"totalNeto":5000}]');
    DECLARE @Doc TABLE(DocumentoProveedorId bigint,YaExistia bit);
    DECLARE @NFactura nvarchar(50)=CONCAT('FAC-',@Suffix),@IdProveedor nvarchar(30)=CONCAT('9',@Suffix),@NRecepcion nvarchar(50)=CONCAT('REC-',@Suffix);
    INSERT @Doc EXEC comp.usp_CrearDocumentoProveedor @EmpresaId=@EmpresaId,@ProveedorIdentificacion=@IdProveedor,@ProveedorRazonSocial=N'Proveedor QA',
        @TipoDocumento='FACTURA',@NumeroDocumento=@NFactura,@FechaDocumento='2026-11-01',@Fuente='MANUAL',
        @SubtotalBruto=5000,@DescuentoTotal=0,@ImpuestoTotal=950,@CargoTotal=0,@TotalPagar=5950,@LineasJson=@Lineas;
    SELECT @DocumentoId=DocumentoProveedorId FROM @Doc;
    DECLARE @Units nvarchar(max)=CONCAT(N'[{"numeroLinea":1,"numeroUnidad":1,"motor":"MOT-',@Suffix,N'","chasis":"CHA-',@Suffix,N'","vin":"VIN-',@Suffix,N'"}]');
    IF @Serial=1 EXEC comp.usp_GuardarUnidadesSerializadasDocumento @EmpresaId=@EmpresaId,@DocumentoProveedorId=@DocumentoId,@UnidadesJson=@Units;
    DECLARE @Prep TABLE(DocumentoProveedorId bigint,RecepcionMercanciaId bigint NULL,CausacionServicioId bigint NULL,LineasInventario int,LineasServicio int);
    INSERT @Prep EXEC comp.usp_PrepararProcesosDocumento @EmpresaId=@EmpresaId,@DocumentoProveedorId=@DocumentoId,
        @BodegaId=@BodegaId,@PeriodoInventarioId=@PeriodoId,@FechaContable='2026-11-01',@NumeroRecepcion=@NRecepcion;
    SELECT @RecepcionId=RecepcionMercanciaId FROM @Prep;
    EXEC inv.usp_ContabilizarRecepcion @EmpresaId=@EmpresaId,@RecepcionMercanciaId=@RecepcionId;
    SELECT @UnidadId=u.UnidadSerializadaId FROM inv.RecepcionMercanciaUnidad u
    JOIN inv.RecepcionMercanciaLinea l ON l.EmpresaId=u.EmpresaId AND l.RecepcionMercanciaLineaId=u.RecepcionMercanciaLineaId
    WHERE l.EmpresaId=@EmpresaId AND l.RecepcionMercanciaId=@RecepcionId;
END;
GO

BEGIN TRANSACTION;
DECLARE @E bigint,@A bigint,@B bigint,@P bigint,@D bigint,@R bigint,@U bigint,@Suffix varchar(12);
EXEC #SeedPurchaseReversal @E OUTPUT,@A OUTPUT,@B OUTPUT,@P OUTPUT,@D OUTPUT,@R OUTPUT,@U OUTPUT,@Suffix OUTPUT;
DECLARE @T bigint=(SELECT TerceroId FROM comp.DocumentoProveedor WHERE EmpresaId=@E AND DocumentoProveedorId=@D);
DECLARE @PC bigint=(SELECT PeriodoContableId FROM core.PeriodoContable WHERE EmpresaId=@E);
INSERT cont.CuentaContable(EmpresaId,Codigo,Nombre,Tipo,Naturaleza) VALUES(@E,'1435',N'Inventario','ACTIVO','D'),(@E,'2205',N'Proveedor','PASIVO','C');
INSERT cont.ComprobanteContable(EmpresaId,IdempotencyKey,Numero,FechaContable,PeriodoContableId,TipoDocumentoOrigen,DocumentoOrigenId,TerceroId,Concepto,TotalDebito,TotalCredito)
VALUES(@E,NEWID(),'COMPRA-LOCAL','2026-11-01',@PC,'RECEPCION_MERCANCIA',@R,@T,N'Compra local',5000,5000);
DECLARE @C bigint=SCOPE_IDENTITY();
INSERT cont.ComprobanteContableLinea(EmpresaId,ComprobanteContableId,NumeroLinea,CuentaContableId,TerceroId,Descripcion,Debito,Credito,CentroCostoCodigo)
SELECT @E,@C,CASE WHEN Codigo='1435' THEN 1 ELSE 2 END,CuentaContableId,@T,N'Compra local',
    CASE WHEN Codigo='1435' THEN 5000 ELSE 0 END,CASE WHEN Codigo='2205' THEN 5000 ELSE 0 END,'CC01'
FROM cont.CuentaContable WHERE EmpresaId=@E;
DECLARE @SnapshotOriginal nvarchar(max)=N'{"Movimientos":[{"Regla":{"Cuenta":"1435","Concepto":"INVENTARIO","CentroCosto":"CC01"},"Valor":5000},{"Regla":{"Cuenta":"2205","Concepto":"PROVEEDOR","CentroCosto":"CC01"},"Valor":-5000}]}';
DECLARE @SnapshotInverso nvarchar(max)=N'{"Movimientos":[{"Regla":{"Cuenta":"1435","Concepto":"INVENTARIO","CentroCosto":"CC01"},"Valor":-5000},{"Regla":{"Cuenta":"2205","Concepto":"PROVEEDOR","CentroCosto":"CC01"},"Valor":5000}]}';
INSERT core.ZeusEnvio(EmpresaId,RecepcionMercanciaId,Estado,Snapshot,Fuente,Documento)
VALUES(@E,@R,'CONTABILIZADO',@SnapshotOriginal,'12','0000000001');

EXEC inv.usp_RevertirEntradaMercancia @EmpresaId=@E,@RecepcionMercanciaId=@R,@PeriodoInventarioId=@P,@FechaContable='2026-11-02',@Motivo=N'Corrección completa de la factura';
EXEC inv.usp_RevertirEntradaMercancia @EmpresaId=@E,@RecepcionMercanciaId=@R,@PeriodoInventarioId=@P,@FechaContable='2026-11-02',@Motivo=N'Corrección completa de la factura';
IF (SELECT COUNT(*) FROM inv.ReversionEntradaMercancia WHERE EmpresaId=@E AND RecepcionMercanciaId=@R)<>1
    THROW 52900,'La reversión completa se duplicó.',1;
IF NOT EXISTS(SELECT 1 FROM inv.UnidadSerializada WHERE EmpresaId=@E AND UnidadSerializadaId=@U AND Estado='BAJA' AND BodegaActualId IS NULL)
    OR NOT EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@E AND BodegaId=@B AND ArticuloId=@A AND Existencia=0 AND ValorTotal=0)
    THROW 52901,'La reversión no retiró el chasis y el valor exacto.',1;
IF NOT EXISTS(SELECT 1 FROM cxp.DocumentoPorPagar WHERE EmpresaId=@E AND DocumentoProveedorId=@D AND SaldoPendiente=0 AND Estado='ANULADA')
   OR (SELECT COUNT(*) FROM cxp.MovimientoProveedor WHERE EmpresaId=@E AND DocumentoOrigenId=@D AND TipoMovimiento='REVERSO' AND FechaMovimiento='2026-11-02' AND Abono=5950)<>1
    THROW 52902,'La reversión no compensó la cartera una sola vez y con la fecha elegida.',1;
DECLARE @CR bigint=(SELECT ComprobanteReversionId FROM inv.ReversionEntradaMercancia WHERE EmpresaId=@E AND RecepcionMercanciaId=@R);
IF @CR IS NULL OR EXISTS(
    SELECT NumeroLinea,CuentaContableId,TerceroId,Descripcion,Credito,Debito,CentroCostoCodigo,ProyectoCodigo FROM cont.ComprobanteContableLinea WHERE EmpresaId=@E AND ComprobanteContableId=@C
    EXCEPT
    SELECT NumeroLinea,CuentaContableId,TerceroId,Descripcion,Debito,Credito,CentroCostoCodigo,ProyectoCodigo FROM cont.ComprobanteContableLinea WHERE EmpresaId=@E AND ComprobanteContableId=@CR)
    THROW 52903,'El comprobante local no invirtió las mismas cuentas, dimensiones e importes.',1;
UPDATE inv.ReversionEntradaMercancia SET ZeusEstado='CONTABILIZADO',ZeusSnapshotOriginal=@SnapshotOriginal,
    ZeusSnapshot=@SnapshotInverso,ZeusFuente='12',ZeusDocumento='0000000002'
WHERE EmpresaId=@E AND RecepcionMercanciaId=@R;
IF (SELECT COUNT(*) FROM cont.vw_AsientoNexo WHERE EmpresaId=@E)<>4
   OR EXISTS(SELECT 1 FROM cont.vw_AsientoNexo WHERE EmpresaId=@E AND Tipo<>'COMPROBANTE_NEXO')
   OR EXISTS(SELECT Cuenta,CentroCosto FROM cont.vw_AsientoNexo WHERE EmpresaId=@E GROUP BY Cuenta,CentroCosto HAVING SUM(Debito-Credito)<>0)
   OR (SELECT SUM(Debito) FROM cont.vw_AsientoNexo WHERE EmpresaId=@E AND Fecha='2026-11-01')<>5000
   OR (SELECT SUM(Debito) FROM cont.vw_AsientoNexo WHERE EmpresaId=@E AND Fecha='2026-11-02')<>5000
    THROW 52910,'El libro Nexo duplicó los snapshots y los comprobantes locales de compra o reversión.',1;

DECLARE @Medida bigint=(SELECT UnidadBaseId FROM inv.Articulo WHERE EmpresaId=@E AND ArticuloId=@A);
DECLARE @NuevaFactura nvarchar(50)=CONCAT('NUEVA-',@Suffix),@NuevaRecepcion nvarchar(50)=CONCAT('REC-NUEVA-',@Suffix),@Proveedor nvarchar(30)=CONCAT('9',@Suffix);
DECLARE @Lineas nvarchar(max)=CONCAT(N'[{"numeroLinea":1,"articuloId":',@A,N',"codigoExterno":"MOTO","descripcion":"Moto corregida","clasificacion":"INVENTARIO","cantidad":1,"unidadMedidaId":',@Medida,N',"factorAUnidadBase":1,"precioUnitario":5500,"subtotalBruto":5500,"descuento":0,"impuesto":1045,"cargo":0,"totalNeto":5500}]');
DECLARE @Doc TABLE(DocumentoProveedorId bigint,YaExistia bit);
INSERT @Doc EXEC comp.usp_CrearDocumentoProveedor @EmpresaId=@E,@ProveedorIdentificacion=@Proveedor,@ProveedorRazonSocial=N'Proveedor QA',
    @TipoDocumento='FACTURA',@NumeroDocumento=@NuevaFactura,@FechaDocumento='2026-11-03',@Fuente='MANUAL',
    @SubtotalBruto=5500,@DescuentoTotal=0,@ImpuestoTotal=1045,@CargoTotal=0,@TotalPagar=6545,@LineasJson=@Lineas;
DECLARE @D2 bigint=(SELECT DocumentoProveedorId FROM @Doc),@R2 bigint;
DECLARE @Units nvarchar(max)=CONCAT(N'[{"numeroLinea":1,"numeroUnidad":1,"motor":"MOT-',@Suffix,N'","chasis":"CHA-',@Suffix,N'","vin":"VIN-',@Suffix,N'"}]');
EXEC comp.usp_GuardarUnidadesSerializadasDocumento @EmpresaId=@E,@DocumentoProveedorId=@D2,@UnidadesJson=@Units;
DECLARE @Prep TABLE(DocumentoProveedorId bigint,RecepcionMercanciaId bigint NULL,CausacionServicioId bigint NULL,LineasInventario int,LineasServicio int);
INSERT @Prep EXEC comp.usp_PrepararProcesosDocumento @EmpresaId=@E,@DocumentoProveedorId=@D2,@BodegaId=@B,@PeriodoInventarioId=@P,@FechaContable='2026-11-03',@NumeroRecepcion=@NuevaRecepcion;
SELECT @R2=RecepcionMercanciaId FROM @Prep;
EXEC inv.usp_ContabilizarRecepcion @EmpresaId=@E,@RecepcionMercanciaId=@R2;
IF (SELECT COUNT(*) FROM inv.UnidadSerializada WHERE EmpresaId=@E)<>1
   OR NOT EXISTS(SELECT 1 FROM inv.UnidadSerializada WHERE EmpresaId=@E AND UnidadSerializadaId=@U AND Estado='DISPONIBLE' AND BodegaActualId=@B)
    THROW 52904,'El reingreso debe reutilizar el mismo chasis dado de baja por la reversión completa.',1;
IF NOT EXISTS(SELECT 1 FROM inv.MovimientoInventarioUnidad mu
    JOIN inv.MovimientoInventario m ON m.EmpresaId=mu.EmpresaId AND m.MovimientoInventarioId=mu.MovimientoInventarioId
    WHERE m.EmpresaId=@E AND m.DocumentoOrigenId=@R2 AND m.TipoDocumentoOrigen='RECEPCION_MERCANCIA'
        AND mu.UnidadSerializadaId=@U AND mu.EstadoAnterior='BAJA' AND mu.EstadoPosterior='DISPONIBLE')
    THROW 52905,'El reingreso no conservó el historial de la unidad.',1;
DECLARE @SalidaKey uniqueidentifier=NEWID(),@UnidadesSalida nvarchar(max)=CONCAT('[',@U,']');
EXEC inv.usp_ContabilizarSalidaSerializada @EmpresaId=@E,@BodegaId=@B,@ArticuloId=@A,@PeriodoInventarioId=@P,
    @FechaMovimiento='2026-11-04',@FechaContable='2026-11-04',@TipoMovimiento='VENTA',@ModuloOrigen='VENTAS',
    @TipoDocumentoOrigen='FACTURA_VENTA',@DocumentoOrigenId=123,@DocumentoLineaOrigenId=1,@NumeroDocumento='VENTA-REINGRESO',
    @CantidadSalida=1,@IdempotencyKey=@SalidaKey,@UnidadesJson=@UnidadesSalida;
IF NOT EXISTS(SELECT 1 FROM inv.MovimientoOrigenInventario mo
    JOIN inv.MovimientoInventario m ON m.EmpresaId=mo.EmpresaId AND m.MovimientoInventarioId=mo.MovimientoInventarioId
    JOIN inv.OrigenInventario o ON o.EmpresaId=mo.EmpresaId AND o.OrigenInventarioId=mo.OrigenInventarioId
    WHERE m.EmpresaId=@E AND m.IdempotencyKey=@SalidaKey AND mo.CantidadSalida=1 AND o.DocumentoOrigenId=@R2)
    THROW 52906,'La venta del reingreso no usó únicamente la recepción corregida.',1;
ROLLBACK;
PRINT 'QA compra revertida: costo, serial, cartera, comprobante, idempotencia y reingreso del mismo chasis.';
GO

BEGIN TRANSACTION;
DECLARE @E bigint,@A bigint,@B bigint,@P bigint,@D bigint,@R bigint,@U bigint,@Suffix varchar(12),@OtraKey uniqueidentifier=NEWID();
EXEC #SeedPurchaseReversal @E OUTPUT,@A OUTPUT,@B OUTPUT,@P OUTPUT,@D OUTPUT,@R OUTPUT,@U OUTPUT,@Suffix OUTPUT,@Serial=0;
EXEC inv.usp_ContabilizarEntrada @EmpresaId=@E,@BodegaId=@B,@ArticuloId=@A,@PeriodoInventarioId=@P,
    @FechaMovimiento='2026-11-02',@FechaContable='2026-11-02',@TipoMovimiento='COMPRA',@ModuloOrigen='COMPRAS',
    @TipoDocumentoOrigen='COMPRA_DIRECTA',@DocumentoOrigenId=101,@NumeroDocumento=N'Otra compra',@CantidadEntrada=1,@CostoUnitarioEntrada=7000,@IdempotencyKey=@OtraKey;
DECLARE @SnapshotOriginal nvarchar(max)=N'{"Movimientos":[{"Regla":{"Cuenta":"1435","Concepto":"INVENTARIO","CentroCosto":"CC02"},"Valor":5000},{"Regla":{"Cuenta":"2205","Concepto":"PROVEEDOR","CentroCosto":"CC02"},"Valor":-5000}]}';
DECLARE @SnapshotInverso nvarchar(max)=N'{"Movimientos":[{"Regla":{"Cuenta":"1435","Concepto":"INVENTARIO","CentroCosto":"CC02"},"Valor":-5000},{"Regla":{"Cuenta":"2205","Concepto":"PROVEEDOR","CentroCosto":"CC02"},"Valor":5000}]}';
INSERT core.ZeusEnvio(EmpresaId,RecepcionMercanciaId,Estado,Snapshot,Fuente,Documento)
VALUES(@E,@R,'CONTABILIZADO',@SnapshotOriginal,'12','0000000003');
EXEC inv.usp_RevertirEntradaMercancia @EmpresaId=@E,@RecepcionMercanciaId=@R,@PeriodoInventarioId=@P,
    @FechaContable='2026-11-03',@Motivo=N'Corrección completa de la factura';
IF NOT EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@E AND BodegaId=@B AND ArticuloId=@A AND Existencia=1 AND ValorTotal=7000 AND CostoPromedio=7000)
    THROW 52908,'La reversión sin seriales debe conservar el costo de las otras compras.',1;
IF NOT EXISTS(SELECT 1 FROM inv.SaldoOrigenBodega s
    JOIN inv.OrigenInventario o ON o.EmpresaId=s.EmpresaId AND o.OrigenInventarioId=s.OrigenInventarioId
    JOIN inv.MovimientoInventario m ON m.EmpresaId=o.EmpresaId AND m.MovimientoInventarioId=o.MovimientoEntradaInicialId
    WHERE s.EmpresaId=@E AND s.BodegaId=@B AND s.CantidadDisponible=1 AND m.IdempotencyKey=@OtraKey)
    THROW 52909,'La reversión sin seriales descontó la capa de otra compra.',1;
UPDATE inv.ReversionEntradaMercancia SET ZeusEstado='PENDIENTE',ZeusSnapshotOriginal=@SnapshotOriginal,ZeusSnapshot=@SnapshotInverso
WHERE EmpresaId=@E AND RecepcionMercanciaId=@R;
IF (SELECT COUNT(*) FROM cont.vw_AsientoNexo WHERE EmpresaId=@E)<>2
    OR EXISTS(SELECT 1 FROM cont.vw_AsientoNexo WHERE EmpresaId=@E AND Tipo='REVERSO_ENTRADA')
    THROW 52911,'El libro Nexo incluyó una reversión pendiente de confirmar en Zeus.',1;
UPDATE inv.ReversionEntradaMercancia SET ZeusEstado='CONTABILIZADO',ZeusFuente='12',ZeusDocumento='0000000004'
WHERE EmpresaId=@E AND RecepcionMercanciaId=@R;
IF (SELECT COUNT(*) FROM cont.vw_AsientoNexo WHERE EmpresaId=@E)<>4
   OR (SELECT COUNT(*) FROM cont.vw_AsientoNexo WHERE EmpresaId=@E AND Tipo='REVERSO_ENTRADA' AND Fecha='2026-11-03' AND Fuente='12' AND Documento='0000000004')<>2
   OR EXISTS(SELECT Cuenta,CentroCosto FROM cont.vw_AsientoNexo WHERE EmpresaId=@E GROUP BY Cuenta,CentroCosto HAVING SUM(Debito-Credito)<>0)
    THROW 52912,'El libro Nexo no compensó las mismas cuentas y centros de la compra y su reversión confirmada.',1;
ROLLBACK;
PRINT 'QA artículo sin seriales: se conserva la cantidad, la capa y el costo de otra compra.';
GO

DECLARE @Case int=1,@E bigint,@A bigint,@B bigint,@P bigint,@D bigint,@R bigint,@U bigint,@Suffix varchar(12),@Expected int;
WHILE @Case<=9
BEGIN
    BEGIN TRANSACTION;
    EXEC #SeedPurchaseReversal @E OUTPUT,@A OUTPUT,@B OUTPUT,@P OUTPUT,@D OUTPUT,@R OUTPUT,@U OUTPUT,@Suffix OUTPUT;
    SET @Expected=CASE @Case WHEN 1 THEN 51744 WHEN 2 THEN 51748 WHEN 3 THEN 51751 WHEN 4 THEN 51765 WHEN 5 THEN 51761 WHEN 6 THEN 51747 WHEN 7 THEN 51741 ELSE 51751 END;
    IF @Case=1 UPDATE core.PeriodoInventario SET Estado='CERRADO' WHERE EmpresaId=@E AND PeriodoInventarioId=@P;
    IF @Case=2
    BEGIN
        UPDATE cxp.DocumentoPorPagar SET SaldoPendiente=SaldoPendiente-100,Estado='PARCIAL' WHERE EmpresaId=@E AND DocumentoProveedorId=@D;
        INSERT cxp.MovimientoProveedor(EmpresaId,TerceroId,DocumentoPorPagarId,TipoMovimiento,FechaMovimiento,NumeroDocumento,Moneda,Cargo,Abono,TipoDocumentoOrigen,DocumentoOrigenId)
        SELECT @E,TerceroId,DocumentoPorPagarId,'PAGO','2026-11-01','PAGO-QA',Moneda,0,100,'EGRESO_QA',1
        FROM cxp.DocumentoPorPagar WHERE EmpresaId=@E AND DocumentoProveedorId=@D;
    END;
    IF @Case=3
    BEGIN
        DECLARE @Destino bigint,@Traslado bigint,@Linea bigint;
        INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@E,'DES',N'Destino'); SET @Destino=SCOPE_IDENTITY();
        INSERT inv.Traslado(EmpresaId,Numero,BodegaOrigenId,BodegaDestinoId,FechaSalida) VALUES(@E,'TR-QA',@B,@Destino,'2026-11-01'); SET @Traslado=SCOPE_IDENTITY();
        INSERT inv.TrasladoLinea(EmpresaId,TrasladoId,NumeroLinea,ArticuloId,CantidadDespachada) VALUES(@E,@Traslado,1,@A,1); SET @Linea=SCOPE_IDENTITY();
        INSERT inv.TrasladoLineaUnidad(EmpresaId,TrasladoLineaId,UnidadSerializadaId) VALUES(@E,@Linea,@U);
        EXEC inv.usp_DespacharTraslado @EmpresaId=@E,@TrasladoId=@Traslado,@PeriodoInventarioId=@P,@FechaContable='2026-11-01';
        EXEC inv.usp_RecibirTraslado @EmpresaId=@E,@TrasladoId=@Traslado,@PeriodoInventarioId=@P,@FechaContable='2026-11-01';
        EXEC inv.usp_RevertirTraslado @EmpresaId=@E,@TrasladoId=@Traslado,@PeriodoInventarioId=@P,@FechaContable='2026-11-01',@Motivo=N'Corrección de bodega destino';
    END;
    IF @Case=4 UPDATE comp.DocumentoProveedorLinea SET Clasificacion='SERVICIO_GASTO' WHERE EmpresaId=@E AND DocumentoProveedorId=@D;
    IF @Case=6 INSERT core.ZeusEnvio(EmpresaId,RecepcionMercanciaId,Estado,Snapshot) VALUES(@E,@R,'PENDIENTE',N'{}');
    IF @Case=8
    BEGIN
        DECLARE @SaleKey uniqueidentifier=NEWID(),@SaleReverseKey uniqueidentifier=NEWID(),@SaleId bigint,@UnitIds nvarchar(max)=CONCAT('[',@U,']');
        EXEC inv.usp_ContabilizarSalidaSerializada @EmpresaId=@E,@BodegaId=@B,@ArticuloId=@A,@PeriodoInventarioId=@P,
            @FechaMovimiento='2026-11-01',@FechaContable='2026-11-01',@TipoMovimiento='VENTA',@ModuloOrigen='VENTAS',
            @TipoDocumentoOrigen='FACTURA_VENTA',@DocumentoOrigenId=124,@DocumentoLineaOrigenId=1,@NumeroDocumento='VENTA-DEVUELTA',
            @CantidadSalida=1,@IdempotencyKey=@SaleKey,@UnidadesJson=@UnitIds;
        SELECT @SaleId=MovimientoInventarioId FROM inv.MovimientoInventario WHERE EmpresaId=@E AND IdempotencyKey=@SaleKey;
        EXEC inv.usp_ReversarMovimientoInventario @EmpresaId=@E,@MovimientoOriginalId=@SaleId,@PeriodoInventarioId=@P,
            @FechaContable='2026-11-01',@Motivo=N'Corrección de la venta de prueba',@IdempotencyKey=@SaleReverseKey;
    END;
    IF @Case=9
    BEGIN
        DECLARE @CostKey uniqueidentifier=NEWID(),@OriginalCostMove bigint=(SELECT MovimientoInventarioId FROM inv.MovimientoInventario
            WHERE EmpresaId=@E AND TipoDocumentoOrigen='RECEPCION_MERCANCIA' AND DocumentoOrigenId=@R);
        EXEC inv.usp_AjustarValorInventario @EmpresaId=@E,@BodegaId=@B,@ArticuloId=@A,@PeriodoInventarioId=@P,@FechaMovimiento='2026-11-01',
            @FechaContable='2026-11-01',@TipoDocumentoOrigen='DISTRIBUCION_COSTO',@DocumentoOrigenId=125,@DocumentoLineaOrigenId=1,
            @NumeroDocumento='COSTO-POSTERIOR',@ValorAjuste=200,@IdempotencyKey=@CostKey,@MovimientoRelacionadoId=@OriginalCostMove;
    END;
    BEGIN TRY
        IF @Case=5
        BEGIN
            DECLARE @Original bigint=(SELECT MovimientoInventarioId FROM inv.MovimientoInventario WHERE EmpresaId=@E AND TipoDocumentoOrigen='RECEPCION_MERCANCIA' AND DocumentoOrigenId=@R),@Key uniqueidentifier=NEWID();
            EXEC inv.usp_ReversarMovimientoInventario @EmpresaId=@E,@MovimientoOriginalId=@Original,@PeriodoInventarioId=@P,
                @FechaContable='2026-11-02',@Motivo=N'Intento genérico de una compra',@IdempotencyKey=@Key;
        END
        ELSE
        BEGIN
            DECLARE @EmpresaSolicitada bigint=CASE WHEN @Case=7 THEN @E+100000 ELSE @E END;
            EXEC inv.usp_RevertirEntradaMercancia @EmpresaId=@EmpresaSolicitada,@RecepcionMercanciaId=@R,@PeriodoInventarioId=@P,
                @FechaContable='2026-11-02',@Motivo=N'Corrección completa de la factura';
        END;
        THROW 52907,'Se aceptó una reversión que debía rechazarse.',1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER()<>@Expected THROW;
    END CATCH;
    ROLLBACK;
    SET @Case+=1;
END;
DROP PROCEDURE #SeedPurchaseReversal;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA controles de reversión: periodo, pagos, venta y traslado regresados, costos posteriores, documento mixto, tenant, ruta genérica y Zeus pendiente.';
GO
