SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
GO
CREATE PROCEDURE #SeedMixedReversal
    @ReceiptPosted bit,@ServicePosted bit,@ReceiptVoucher bit,
    @E bigint OUTPUT,@A bigint OUTPUT,@B bigint OUTPUT,@P bigint OUTPUT,
    @D bigint OUTPUT,@R bigint OUTPUT,@CS bigint OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Suffix varchar(12)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12);
    INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('MR-',@Suffix),CONCAT('8',RIGHT(@Suffix,9)),N'Compra mixta reversible');
    SET @E=SCOPE_IDENTITY();
    INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@E);
    INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES(@E,'UND',N'Unidad','und');
    DECLARE @Medida bigint=SCOPE_IDENTITY();
    INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId) VALUES(@E,'ART',N'Artículo de compra mixta','INVENTARIO',1,@Medida);
    SET @A=SCOPE_IDENTITY();
    INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@E,'ORI',N'Bodega de compra mixta'); SET @B=SCOPE_IDENTITY();
    INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@E,'2026-11','2026-11-01','2026-11-30'); SET @P=SCOPE_IDENTITY();
    INSERT core.PeriodoContable(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@E,'2026-11','2026-11-01','2026-11-30');
    DECLARE @PC bigint=SCOPE_IDENTITY();
    INSERT cont.CuentaContable(EmpresaId,Codigo,Nombre,Tipo,Naturaleza) VALUES
        (@E,'1435',N'Inventario','ACTIVO','D'),(@E,'5135',N'Servicios','GASTO','D'),
        (@E,'2408',N'IVA descontable','ACTIVO','D'),(@E,'2205',N'Proveedor','PASIVO','C');
    DECLARE @Lineas nvarchar(max)=CONCAT(N'[{"numeroLinea":1,"articuloId":',@A,
        N',"codigoExterno":"ART","descripcion":"Artículo","clasificacion":"INVENTARIO","cantidad":1,"unidadMedidaId":',@Medida,
        N',"factorAUnidadBase":1,"precioUnitario":1000,"subtotalBruto":1000,"descuento":0,"impuesto":190,"cargo":0,"totalNeto":1000},',
        N'{"numeroLinea":2,"descripcion":"Servicio","clasificacion":"SERVICIO_GASTO","cantidad":1,"factorAUnidadBase":1,"precioUnitario":200,"subtotalBruto":200,"descuento":0,"impuesto":38,"cargo":0,"totalNeto":200,"cuentaContableCodigo":"5135"}]');
    DECLARE @Doc TABLE(DocumentoProveedorId bigint,YaExistia bit);
    DECLARE @NFactura nvarchar(50)=CONCAT('FAC-',@Suffix),@IdProveedor nvarchar(30)=CONCAT('9',@Suffix),@NRecepcion nvarchar(50)=CONCAT('REC-',@Suffix),@NCausacion nvarchar(50)=CONCAT('CAU-',@Suffix);
    INSERT @Doc EXEC comp.usp_CrearDocumentoProveedor @EmpresaId=@E,@ProveedorIdentificacion=@IdProveedor,@ProveedorRazonSocial=N'Proveedor mixto',
        @TipoDocumento='FACTURA',@NumeroDocumento=@NFactura,@FechaDocumento='2026-11-01',@Fuente='MANUAL',
        @SubtotalBruto=1200,@DescuentoTotal=0,@ImpuestoTotal=228,@CargoTotal=0,@TotalPagar=1428,@LineasJson=@Lineas;
    SELECT @D=DocumentoProveedorId FROM @Doc;
    DECLARE @Prep TABLE(DocumentoProveedorId bigint,RecepcionMercanciaId bigint NULL,CausacionServicioId bigint NULL,LineasInventario int,LineasServicio int);
    INSERT @Prep EXEC comp.usp_PrepararProcesosDocumento @EmpresaId=@E,@DocumentoProveedorId=@D,
        @BodegaId=@B,@PeriodoInventarioId=@P,@FechaContable='2026-11-01',@NumeroRecepcion=@NRecepcion,@NumeroCausacion=@NCausacion;
    SELECT @R=RecepcionMercanciaId,@CS=CausacionServicioId FROM @Prep;
    UPDATE comp.CausacionServicio SET FechaContable='2026-11-02',CentroCostoCodigo='SERV',ProyectoCodigo='PROY'
    WHERE EmpresaId=@E AND CausacionServicioId=@CS;
    UPDATE comp.CausacionServicioLinea SET CuentaContableCodigo='5135' WHERE EmpresaId=@E AND CausacionServicioId=@CS;
    IF @ReceiptPosted=1 EXEC inv.usp_ContabilizarRecepcion @EmpresaId=@E,@RecepcionMercanciaId=@R;
    IF @ServicePosted=1 EXEC comp.usp_ContabilizarCausacionServicio @EmpresaId=@E,@CausacionServicioId=@CS,@PeriodoContableId=@PC,
        @CuentaImpuestoCodigo='2408',@CuentaPorPagarCodigo='2205';
    IF @ReceiptVoucher=1
    BEGIN
        DECLARE @T bigint=(SELECT TerceroId FROM comp.DocumentoProveedor WHERE EmpresaId=@E AND DocumentoProveedorId=@D);
        INSERT cont.ComprobanteContable(EmpresaId,IdempotencyKey,Numero,FechaContable,PeriodoContableId,TipoDocumentoOrigen,DocumentoOrigenId,TerceroId,Concepto,TotalDebito,TotalCredito)
        VALUES(@E,NEWID(),'COMPRA-INVENTARIO','2026-11-01',@PC,'RECEPCION_MERCANCIA',@R,@T,N'Inventario de la compra mixta',1190,1190);
        DECLARE @C bigint=SCOPE_IDENTITY();
        INSERT cont.ComprobanteContableLinea(EmpresaId,ComprobanteContableId,NumeroLinea,CuentaContableId,TerceroId,Descripcion,Debito,Credito)
        SELECT @E,@C,CASE Codigo WHEN '1435' THEN 1 WHEN '2408' THEN 2 ELSE 3 END,CuentaContableId,@T,N'Compra mixta',
            CASE Codigo WHEN '1435' THEN 1000 WHEN '2408' THEN 190 ELSE 0 END,CASE WHEN Codigo='2205' THEN 1190 ELSE 0 END
        FROM cont.CuentaContable WHERE EmpresaId=@E AND Codigo IN('1435','2408','2205');
    END;
END;
GO

DECLARE @Case int=1,@E bigint,@A bigint,@B bigint,@P bigint,@D bigint,@R bigint,@CS bigint;
WHILE @Case<=8
BEGIN
    BEGIN TRANSACTION;
    DECLARE @ReceiptPosted bit=CASE WHEN @Case IN(3,8) THEN 0 ELSE 1 END;
    DECLARE @ServicePosted bit=CASE WHEN @Case IN(2,8) THEN 0 ELSE 1 END;
    DECLARE @ReceiptVoucher bit=CASE WHEN @Case=4 THEN 1 ELSE 0 END;
    EXEC #SeedMixedReversal @ReceiptPosted,@ServicePosted,@ReceiptVoucher,@E OUTPUT,@A OUTPUT,@B OUTPUT,@P OUTPUT,@D OUTPUT,@R OUTPUT,@CS OUTPUT;
    DECLARE @ReversalId bigint,@Fecha date='2026-11-03',@Expected int=NULL;
    IF @Case=5
    BEGIN
        UPDATE cxp.DocumentoPorPagar SET SaldoPendiente=SaldoPendiente-10,Estado='PARCIAL' WHERE EmpresaId=@E AND DocumentoProveedorId=@D;
        SET @Expected=51748;
    END;
    IF @Case=6
    BEGIN
        SET @Fecha='2026-11-01';
        SET @Expected=51764;
    END;
    IF @Case=7
    BEGIN
        UPDATE core.PeriodoContable SET Estado='CERRADO' WHERE EmpresaId=@E;
        SET @Expected=51754;
    END;
    IF @Case=8 SET @Expected=51742;
    IF @Expected IS NULL
    BEGIN
        DECLARE @EstadoRecepcionAnterior varchar(15)=(SELECT Estado FROM inv.RecepcionMercancia WHERE EmpresaId=@E AND RecepcionMercanciaId=@R);
        EXEC inv.usp_RevertirEntradaMercancia @EmpresaId=@E,@RecepcionMercanciaId=@R,@PeriodoInventarioId=@P,@FechaContable=@Fecha,@Motivo=N'Corrección completa de compra mixta';
        EXEC inv.usp_RevertirEntradaMercancia @EmpresaId=@E,@RecepcionMercanciaId=@R,@PeriodoInventarioId=@P,@FechaContable=@Fecha,@Motivo=N'Corrección completa de compra mixta';
        SELECT @ReversalId=ReversionEntradaMercanciaId FROM inv.ReversionEntradaMercancia WHERE EmpresaId=@E AND RecepcionMercanciaId=@R;
        IF @ReversalId IS NULL OR NOT EXISTS(SELECT 1 FROM comp.DocumentoProveedor WHERE EmpresaId=@E AND DocumentoProveedorId=@D AND Estado='REVERTIDO')
            THROW 52920,'No se revirtió el documento mixto completo.',1;
        IF NOT EXISTS(SELECT 1 FROM inv.RecepcionMercancia WHERE EmpresaId=@E AND RecepcionMercanciaId=@R AND Estado=CASE WHEN @ReceiptPosted=1 THEN 'REVERTIDA' ELSE 'CANCELADA' END)
           OR NOT EXISTS(SELECT 1 FROM comp.CausacionServicio WHERE EmpresaId=@E AND CausacionServicioId=@CS AND Estado=CASE WHEN @ServicePosted=1 THEN 'REVERTIDA' ELSE 'CANCELADA' END)
            THROW 52921,'La compra mixta no revirtió lo contabilizado y canceló lo pendiente.',1;
        IF @ReceiptPosted=0 AND NOT EXISTS(SELECT 1 FROM audit.Evento
            WHERE EmpresaId=@E AND Operacion='ENTRADA_MERCANCIA_REVERTIDA' AND EntidadId=CONVERT(nvarchar(100),@R)
                AND JSON_VALUE(ValoresAnteriores,'$.estado')=@EstadoRecepcionAnterior
                AND JSON_VALUE(ValoresPosteriores,'$.estado')='CANCELADA')
            THROW 52931,'La auditoría de la entrada pendiente debe conservar su estado anterior y su cancelación real.',1;
        IF @ReceiptPosted=1 AND NOT EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@E AND BodegaId=@B AND ArticuloId=@A AND Existencia=0 AND ValorTotal=0)
            THROW 52922,'La reversión mixta no retiró el costo y la mercancía originales.',1;
        IF @ReceiptPosted=0 AND EXISTS(SELECT 1 FROM inv.MovimientoInventario WHERE EmpresaId=@E)
            THROW 52923,'La reversión de una recepción pendiente creó movimientos de inventario.',1;
        IF @ReceiptPosted=1 AND @ServicePosted=1
        BEGIN
            IF (SELECT COUNT(*) FROM cxp.DocumentoPorPagar WHERE EmpresaId=@E AND DocumentoProveedorId=@D AND Estado='ANULADA' AND ValorOriginal=1428 AND SaldoPendiente=0)<>1
               OR (SELECT COUNT(*) FROM cxp.MovimientoProveedor WHERE EmpresaId=@E AND TipoMovimiento='REVERSO' AND DocumentoOrigenId=@D AND Abono=1428)<>1
                THROW 52924,'La factura mixta debe compensar su única cuenta por pagar completa una vez.',1;
        END
        ELSE IF EXISTS(SELECT 1 FROM cxp.DocumentoPorPagar WHERE EmpresaId=@E)
            THROW 52925,'Se creó cartera para una compra cuya contabilización estaba incompleta.',1;
        IF (SELECT COUNT(*) FROM inv.ReversionEntradaComprobante WHERE EmpresaId=@E AND ReversionEntradaMercanciaId=@ReversalId AND ComprobanteReversionId IS NOT NULL)<>CONVERT(int,@ServicePosted)+CONVERT(int,@ReceiptVoucher)
            THROW 52926,'No se relacionaron todos los comprobantes locales y sus inversos.',1;
        IF EXISTS(
            SELECT cp.ComprobanteOriginalId,l.NumeroLinea,l.CuentaContableId,l.TerceroId,l.Descripcion,l.Credito,l.Debito,l.CentroCostoCodigo,l.ProyectoCodigo
            FROM inv.ReversionEntradaComprobante cp
            JOIN cont.ComprobanteContableLinea l ON l.EmpresaId=cp.EmpresaId AND l.ComprobanteContableId=cp.ComprobanteOriginalId
            WHERE cp.EmpresaId=@E
            EXCEPT
            SELECT cp.ComprobanteOriginalId,l.NumeroLinea,l.CuentaContableId,l.TerceroId,l.Descripcion,l.Debito,l.Credito,l.CentroCostoCodigo,l.ProyectoCodigo
            FROM inv.ReversionEntradaComprobante cp
            JOIN cont.ComprobanteContableLinea l ON l.EmpresaId=cp.EmpresaId AND l.ComprobanteContableId=cp.ComprobanteReversionId
            WHERE cp.EmpresaId=@E)
            THROW 52927,'Un inverso de servicios o inventario perdió su cuenta, tercero, centro, proyecto o importe.',1;
        IF EXISTS(SELECT Cuenta,CentroCosto FROM cont.vw_AsientoNexo WHERE EmpresaId=@E GROUP BY Cuenta,CentroCosto HAVING SUM(Debito-Credito)<>0)
            THROW 52928,'Los comprobantes locales de la compra mixta y su reversión no netean cero.',1;
        IF @Case IN(1,4)
        BEGIN
            DECLARE @Snapshot nvarchar(max)=N'{"Origen":{"Total":1428},"Movimientos":[{"Regla":{"Cuenta":"1435","Concepto":"INVENTARIO"},"Valor":1000},{"Regla":{"Cuenta":"5135","Concepto":"SERVICIO","CentroCosto":"SERV"},"Valor":200},{"Regla":{"Cuenta":"2408","Concepto":"IVA"},"Valor":228},{"Regla":{"Cuenta":"2205","Concepto":"PROVEEDOR"},"Valor":-1428}]}';
            DECLARE @Inverso nvarchar(max)=N'{"Origen":{"Total":1428},"Movimientos":[{"Regla":{"Cuenta":"1435","Concepto":"INVENTARIO"},"Valor":-1000},{"Regla":{"Cuenta":"5135","Concepto":"SERVICIO","CentroCosto":"SERV"},"Valor":-200},{"Regla":{"Cuenta":"2408","Concepto":"IVA"},"Valor":-228},{"Regla":{"Cuenta":"2205","Concepto":"PROVEEDOR"},"Valor":1428}]}';
            INSERT core.ZeusEnvio(EmpresaId,RecepcionMercanciaId,Estado,Snapshot,Fuente,Documento) VALUES(@E,@R,'CONTABILIZADO',@Snapshot,'12','0000000011');
            UPDATE inv.ReversionEntradaMercancia SET ZeusEstado='CONTABILIZADO',ZeusSnapshotOriginal=@Snapshot,ZeusSnapshot=@Inverso,ZeusFuente='12',ZeusDocumento='0000000012'
            WHERE EmpresaId=@E AND ReversionEntradaMercanciaId=@ReversalId;
            IF (SELECT COUNT(*) FROM cont.vw_AsientoNexo WHERE EmpresaId=@E)<>8
               OR EXISTS(SELECT 1 FROM cont.vw_AsientoNexo WHERE EmpresaId=@E AND Tipo='COMPROBANTE_NEXO')
               OR EXISTS(SELECT Cuenta,CentroCosto FROM cont.vw_AsientoNexo WHERE EmpresaId=@E GROUP BY Cuenta,CentroCosto HAVING SUM(Debito-Credito)<>0)
                THROW 52929,'La vista duplicó el servicio local y el snapshot completo de la factura mixta.',1;
        END;
    END
    ELSE
    BEGIN
        BEGIN TRY
            EXEC inv.usp_RevertirEntradaMercancia @EmpresaId=@E,@RecepcionMercanciaId=@R,@PeriodoInventarioId=@P,@FechaContable=@Fecha,@Motivo=N'Corrección completa de compra mixta';
            THROW 52930,'Se aceptó una reversión mixta que debía rechazarse.',1;
        END TRY
        BEGIN CATCH
            IF ERROR_NUMBER()<>@Expected THROW;
        END CATCH;
    END;
    ROLLBACK;
    SET @Case+=1;
END;
DROP PROCEDURE #SeedMixedReversal;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA reversión mixta: ambas etapas contabilizadas o pendientes, todos los comprobantes, cartera única, vista sin duplicados, fechas, periodos y pagos.';
GO
