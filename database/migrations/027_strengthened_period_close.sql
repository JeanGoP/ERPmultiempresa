SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='027_strengthened_period_close')
BEGIN
    BEGIN TRANSACTION;
    ALTER TABLE inv.CierrePeriodoInventarioSaldo ADD DeterioroAcumulado decimal(20,4) NOT NULL CONSTRAINT DF_CierreSaldo_Deterioro DEFAULT 0,
        ValorNetoContable decimal(20,4) NOT NULL CONSTRAINT DF_CierreSaldo_ValorNeto DEFAULT 0;
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('027_strengthened_period_close',N'Cierre condicionado a reconciliación y fotografía de deterioro y valor neto');
    COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_CerrarPeriodoInventario
    @EmpresaId bigint,@PeriodoInventarioId bigint,@UsuarioId bigint=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    DECLARE @Estado varchar(15),@Inicio date,@Fin date,@Codigo char(7);
    SELECT @Estado=Estado,@Inicio=FechaInicio,@Fin=FechaFin,@Codigo=Codigo FROM core.PeriodoInventario WITH(UPDLOCK,HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoInventarioId;
    IF @Estado IS NULL THROW 51870,'El periodo no existe o no pertenece a la empresa.',1;
    IF @Estado='CERRADO'
    BEGIN COMMIT; SELECT @PeriodoInventarioId PeriodoInventarioId,@Estado Estado,(SELECT MAX(VersionCierre) FROM inv.CierrePeriodoInventario WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoInventarioId) VersionCierre,CAST(1 AS bit) YaExistia; RETURN; END;
    IF @Estado NOT IN('ABIERTO','REABIERTO') THROW 51871,'El periodo no está disponible para cierre.',1;
    UPDATE core.PeriodoInventario SET Estado='EN_CIERRE' WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoInventarioId;
    IF EXISTS(SELECT 1 FROM inv.RecepcionMercancia WHERE EmpresaId=@EmpresaId AND FechaContable BETWEEN @Inicio AND @Fin AND Estado IN('BORRADOR','VALIDADA')) THROW 51872,'Existen recepciones pendientes en el periodo.',1;
    IF EXISTS(SELECT 1 FROM inv.DevolucionProveedor WHERE EmpresaId=@EmpresaId AND FechaContable BETWEEN @Inicio AND @Fin AND Estado IN('BORRADOR','VALIDADA')) THROW 51873,'Existen devoluciones de compra pendientes en el periodo.',1;
    IF EXISTS(SELECT 1 FROM inv.DevolucionVenta WHERE EmpresaId=@EmpresaId AND FechaContable BETWEEN @Inicio AND @Fin AND Estado IN('BORRADOR','VALIDADA')) THROW 51876,'Existen devoluciones de venta pendientes en el periodo.',1;
    IF EXISTS(SELECT 1 FROM inv.ConteoFisico WHERE EmpresaId=@EmpresaId AND CONVERT(date,FechaCorte) BETWEEN @Inicio AND @Fin AND Estado IN('EN_CONTEO','RECONTEO','EN_REVISION','APROBADO')) THROW 51874,'Existen conteos físicos activos en el periodo.',1;
    IF EXISTS(SELECT 1 FROM inv.SalidaExcepcionalNegativa WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoInventarioId AND Estado='PENDIENTE') THROW 51877,'Existen salidas excepcionales pendientes de regularización.',1;
    IF EXISTS(SELECT 1 FROM inv.Traslado WHERE EmpresaId=@EmpresaId AND CONVERT(date,FechaSalida) BETWEEN @Inicio AND @Fin AND Estado IN('BORRADOR','DESPACHADO','EN_TRANSITO','RECIBIDO_PARCIAL')) THROW 51878,'Existen traslados sin completar en el periodo.',1;
    IF EXISTS
    (
        SELECT 1 FROM cost.DistribucionCosto d JOIN cost.DistribucionCostoLinea dl ON dl.EmpresaId=d.EmpresaId AND dl.DistribucionCostoId=d.DistribucionCostoId
        JOIN inv.RecepcionMercanciaLinea rl ON rl.EmpresaId=dl.EmpresaId AND rl.RecepcionMercanciaLineaId=dl.RecepcionMercanciaLineaId
        JOIN inv.RecepcionMercancia r ON r.EmpresaId=rl.EmpresaId AND r.RecepcionMercanciaId=rl.RecepcionMercanciaId
        WHERE d.EmpresaId=@EmpresaId AND r.PeriodoInventarioId=@PeriodoInventarioId AND d.Estado IN('CALCULADA','APROBADA')
    ) THROW 51879,'Existen costos adicionales calculados o aprobados sin aplicar.',1;
    IF EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND (Existencia<0 OR ValorTotal<0 OR CostoPromedio<0 OR ABS(ValorTotal-CAST(Existencia*CostoPromedio AS decimal(20,4)))>0.01)) THROW 51875,'Los saldos contienen negativos o diferencias de valoración.',1;

    DECLARE @Rec TABLE(ReconciliacionInventarioId bigint,Estado varchar(15),Diferencias int);
    INSERT @Rec EXEC inv.usp_ReconciliarInventario @EmpresaId=@EmpresaId,@UsuarioId=@UsuarioId;
    IF EXISTS(SELECT 1 FROM @Rec WHERE Estado<>'CUADRADO' OR Diferencias<>0) THROW 51881,'La reconciliación de inventario contiene diferencias; el cierre fue bloqueado.',1;

    DECLARE @Version int=COALESCE((SELECT MAX(VersionCierre) FROM inv.CierrePeriodoInventario WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoInventarioId),0)+1,@CierreId bigint;
    INSERT inv.CierrePeriodoInventario(EmpresaId,PeriodoInventarioId,VersionCierre,TotalReferencias,TotalExistencia,TotalValor,CerradoPorUsuarioId)
    SELECT @EmpresaId,@PeriodoInventarioId,@Version,COUNT(*),COALESCE(SUM(CAST(Existencia AS decimal(28,6))),0),COALESCE(SUM(CAST(ValorTotal AS decimal(28,4))),0),@UsuarioId FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId;
    SET @CierreId=SCOPE_IDENTITY();
    INSERT inv.CierrePeriodoInventarioSaldo(EmpresaId,CierrePeriodoInventarioId,BodegaId,ArticuloId,Existencia,CostoPromedio,ValorTotal,UltimoMovimientoId,DeterioroAcumulado,ValorNetoContable)
    SELECT @EmpresaId,@CierreId,s.BodegaId,s.ArticuloId,s.Existencia,s.CostoPromedio,s.ValorTotal,s.UltimoMovimientoId,COALESCE(d.DeterioroAcumulado,0),s.ValorTotal-COALESCE(d.DeterioroAcumulado,0)
    FROM inv.SaldoArticuloBodega s LEFT JOIN inv.SaldoDeterioroInventario d ON d.EmpresaId=s.EmpresaId AND d.BodegaId=s.BodegaId AND d.ArticuloId=s.ArticuloId WHERE s.EmpresaId=@EmpresaId;
    UPDATE core.PeriodoInventario SET Estado='CERRADO',CerradoEnUtc=SYSUTCDATETIME(),CerradoPorUsuarioId=@UsuarioId,MotivoReapertura=NULL WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoInventarioId;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresPosteriores,AplicacionOrigen)
    VALUES(@EmpresaId,@UsuarioId,'PERIODO_INVENTARIO_CERRADO','core.PeriodoInventario',CONVERT(nvarchar(100),@PeriodoInventarioId),@Codigo,CONCAT(N'{"version":',@Version,N',"cierreId":',@CierreId,N',"reconciliacionId":',(SELECT ReconciliacionInventarioId FROM @Rec),N'}'),'INVENTARIO');
    COMMIT;
    SELECT @PeriodoInventarioId PeriodoInventarioId,CAST('CERRADO' AS varchar(15)) Estado,@Version VersionCierre,CAST(0 AS bit) YaExistia;
END;
GO
