/*
    Reinicio controlado para una demostracion de compras e inventario.
    Compatible con el esquema hasta la migracion 042.

    CONSERVA:
      - empresa, usuarios, roles y permisos;
      - bodegas, ubicaciones y periodos (los periodos cerrados se reabren);
      - proveedores, articulos, unidades y homologaciones;
      - auditoria (audit.Evento), porque en un ERP no debe borrarse.

    ELIMINA PARA UNA SOLA EMPRESA:
      - documentos de proveedor y sus lineas/seriales;
      - recepciones y causaciones originadas por esos documentos;
      - unidades serializadas, lotes, Kardex y saldos;
      - operaciones dependientes de inventario, costos y Outbox;
      - alertas y aprobaciones operativas de la empresa.

    IMPORTANTE:
      - Ejecute el borrado durante una ventana de mantenimiento, sin usuarios
        registrando operaciones en la empresa seleccionada.
      - Los IDENTITY no se reinician: son globales y pueden contener datos de
        otras empresas. La informacion operativa queda vacia, aunque el proximo
        identificador interno no vuelva a ser 1.
      - El propio reinicio se registra en audit.Evento.

    USO:
      1. Cambie @EmpresaCodigo por el codigo exacto de la empresa.
      2. Ejecute una vez con @Confirmacion = N'SOLO-VISTA-PREVIA'.
      3. Revise los conteos que se muestran.
      4. Para borrar, use @Confirmacion = N'BORRAR-' + el codigo de empresa.

    Ejemplo:
      @EmpresaCodigo = N'MONTE'
      @Confirmacion  = N'BORRAR-MONTE'
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;

DECLARE @EmpresaCodigo nvarchar(20) = N'CAMBIAR-AQUI';
DECLARE @Confirmacion nvarchar(100) = N'SOLO-VISTA-PREVIA';
DECLARE @EmpresaId bigint;
DECLARE @ResumenAntes nvarchar(max);

EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;

IF @EmpresaCodigo = N'CAMBIAR-AQUI'
BEGIN
    SELECT EmpresaId,Codigo,Nit,RazonSocial,Activa
    FROM core.Empresa
    ORDER BY EmpresaId;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
    THROW 52090, 'Defina @EmpresaCodigo con el codigo exacto. No se borro informacion.', 1;
END;

SELECT @EmpresaId=EmpresaId
FROM core.Empresa
WHERE Codigo=@EmpresaCodigo;

IF @EmpresaId IS NULL
BEGIN
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
    THROW 52091, 'La empresa indicada no existe. No se borro informacion.', 1;
END;

PRINT N'Empresa seleccionada:';
SELECT EmpresaId,Codigo,Nit,RazonSocial,Activa
FROM core.Empresa
WHERE EmpresaId=@EmpresaId;

PRINT N'Resumen antes del reinicio:';
SELECT
    (SELECT COUNT(*) FROM comp.DocumentoProveedor WHERE EmpresaId=@EmpresaId) AS EntradasGuardadas,
    (SELECT COUNT(*) FROM inv.RecepcionMercancia WHERE EmpresaId=@EmpresaId) AS Recepciones,
    (SELECT COUNT(*) FROM inv.RecepcionMercancia WHERE EmpresaId=@EmpresaId AND Estado='CONTABILIZADA') AS RecepcionesContabilizadas,
    (SELECT COUNT(*) FROM inv.RecepcionMercanciaRevisionUnidad WHERE EmpresaId=@EmpresaId) AS RevisionesFisicas,
    (SELECT COUNT(*) FROM inv.RecepcionMercanciaRevisionUnidad WHERE EmpresaId=@EmpresaId AND EstadoFisico IN('RECIBIDA_NOVEDAD','NO_RECIBIDA') AND GestionadaEnUtc IS NULL) AS NovedadesPendientes,
    (SELECT COUNT(*) FROM comp.CausacionServicio WHERE EmpresaId=@EmpresaId) AS CausacionesServicio,
    (SELECT COUNT(*) FROM comp.DocumentoProveedorLineaUnidad WHERE EmpresaId=@EmpresaId) AS SerialesEnDocumentos,
    (SELECT COUNT(*) FROM inv.UnidadSerializada WHERE EmpresaId=@EmpresaId) AS UnidadesSerializadasInventario,
    (SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId) AS MovimientosKardex,
    (SELECT COUNT(*) FROM core.OutboxEvento WHERE EmpresaId=@EmpresaId) AS EventosOutbox,
    (SELECT COUNT(*) FROM core.AlertaOperacion WHERE EmpresaId=@EmpresaId) AS AlertasOperativas,
    (SELECT COUNT(*) FROM seg.AprobacionOperacion WHERE EmpresaId=@EmpresaId) AS AprobacionesOperativas,
    (SELECT COUNT(*) FROM core.PeriodoInventario WHERE EmpresaId=@EmpresaId AND Estado<>'ABIERTO') AS PeriodosInventarioNoAbiertos,
    (SELECT COUNT(*) FROM core.PeriodoContable WHERE EmpresaId=@EmpresaId AND Estado<>'ABIERTO') AS PeriodosContablesNoAbiertos,
    (SELECT COALESCE(SUM(Existencia),0) FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId) AS ExistenciaTotal,
    (SELECT COALESCE(SUM(ValorTotal),0) FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId) AS ValorInventario;

SELECT @ResumenAntes=(
    SELECT
        (SELECT COUNT(*) FROM comp.DocumentoProveedor WHERE EmpresaId=@EmpresaId) AS documentosProveedor,
        (SELECT COUNT(*) FROM inv.RecepcionMercancia WHERE EmpresaId=@EmpresaId) AS recepciones,
        (SELECT COUNT(*) FROM comp.CausacionServicio WHERE EmpresaId=@EmpresaId) AS causaciones,
        (SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId) AS movimientosKardex,
        (SELECT COUNT(*) FROM inv.UnidadSerializada WHERE EmpresaId=@EmpresaId) AS unidadesSerializadas,
        (SELECT COALESCE(SUM(Existencia),0) FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId) AS existenciaTotal,
        (SELECT COALESCE(SUM(ValorTotal),0) FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId) AS valorInventario
    FOR JSON PATH,WITHOUT_ARRAY_WRAPPER
);

IF @Confirmacion<>CONCAT(N'BORRAR-',@EmpresaCodigo)
BEGIN
    PRINT N'SOLO VISTA PREVIA: no se borro informacion.';
    PRINT CONCAT(N'Para ejecutar use: DECLARE @Confirmacion = N''BORRAR-',@EmpresaCodigo,N''';');
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
    RETURN;
END;

-- Permite repetir el script en la misma ventana/sesion de SSMS.
DROP TABLE IF EXISTS #Comprobantes;
DROP TABLE IF EXISTS #Causaciones;

CREATE TABLE #Causaciones(CausacionServicioId bigint NOT NULL PRIMARY KEY);
INSERT #Causaciones(CausacionServicioId)
SELECT CausacionServicioId FROM comp.CausacionServicio WHERE EmpresaId=@EmpresaId;

CREATE TABLE #Comprobantes(ComprobanteContableId bigint NOT NULL PRIMARY KEY);
INSERT #Comprobantes(ComprobanteContableId)
SELECT DISTINCT c.ComprobanteContableId
FROM comp.CausacionServicio c
WHERE c.EmpresaId=@EmpresaId AND c.ComprobanteContableId IS NOT NULL
UNION
SELECT cc.ComprobanteContableId
FROM cont.ComprobanteContable cc
JOIN #Causaciones c ON c.CausacionServicioId=cc.DocumentoOrigenId
WHERE cc.EmpresaId=@EmpresaId AND cc.TipoDocumentoOrigen='CAUSACION_SERVICIO';

BEGIN TRY
    BEGIN TRANSACTION;

    -- Estas bitacoras son inmutables en operacion normal. Solo se habilita
    -- su borrado dentro de este reinicio administrativo y transaccional.
    DISABLE TRIGGER inv.TR_MovimientoInventario_Inmutable ON inv.MovimientoInventario;
    DISABLE TRIGGER inv.TR_MovimientoInventarioUnidad_Inmutable ON inv.MovimientoInventarioUnidad;
    DISABLE TRIGGER cont.TR_ComprobanteContable_Inmutable ON cont.ComprobanteContable;
    DISABLE TRIGGER cont.TR_ComprobanteContableLinea_Inmutable ON cont.ComprobanteContableLinea;

    -- Integraciones y alertas generadas por las operaciones que se retiran.
    DELETE FROM core.EntregaIntegracion WHERE EmpresaId=@EmpresaId;
    DELETE FROM core.AlertaOperacion WHERE EmpresaId=@EmpresaId;
    DELETE FROM core.OutboxEvento WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.MovimientoInventarioArchivo WHERE EmpresaId=@EmpresaId;

    -- Trazabilidad de unidades y operaciones posteriores.
    DELETE FROM inv.MovimientoInventarioUnidad WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.TrasladoLineaUnidad WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.DevolucionProveedorLineaUnidad WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.DevolucionVentaLineaUnidad WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.SolicitudSalidaSerializadaUnidad WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.SolicitudSalidaSerializada WHERE EmpresaId=@EmpresaId;

    -- Devoluciones, traslados y controles de inventario.
    DELETE FROM inv.DevolucionProveedorLinea WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.DevolucionProveedor WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.DevolucionVentaLinea WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.DevolucionVenta WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.TrasladoLinea WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.Traslado WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.BloqueoConteoFisico WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.ConteoCaptura WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.ConteoFisicoLinea WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.ConteoFisico WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.ReconciliacionInventarioDetalle WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.ReconciliacionInventario WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.CierrePeriodoInventarioSaldo WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.CierrePeriodoInventario WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.ReversionMovimientoInventario WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.SalidaExcepcionalNegativa WHERE EmpresaId=@EmpresaId;

    -- Ya no quedan operaciones que dependan de estas aprobaciones.
    DELETE FROM seg.AprobacionOperacion WHERE EmpresaId=@EmpresaId;

    -- Deterioros y costos dependientes del Kardex o de las recepciones.
    DELETE FROM inv.SaldoDeterioroInventario WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.DeterioroInventario WHERE EmpresaId=@EmpresaId;
    DELETE FROM cost.AplicacionCostoAdquisicion WHERE EmpresaId=@EmpresaId;
    DELETE FROM cost.DistribucionCostoObjetivo WHERE EmpresaId=@EmpresaId;
    DELETE FROM cost.DistribucionCostoLinea WHERE EmpresaId=@EmpresaId;
    DELETE FROM cost.DistribucionCosto WHERE EmpresaId=@EmpresaId;
    DELETE FROM cost.DocumentoCostoAdquisicion WHERE EmpresaId=@EmpresaId;
    DELETE FROM cost.SaldoCostoLibroBodega WHERE EmpresaId=@EmpresaId;
    DELETE FROM cost.MovimientoCostoLibro WHERE EmpresaId=@EmpresaId;

    -- Origenes, saldos y Kardex.
    DELETE FROM inv.MovimientoOrigenInventario WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.SaldoOrigenBodega WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.OrigenInventario WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.SaldoArticuloLoteUbicacion WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.SaldoArticuloUbicacion WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId;

    -- Seriales materializados, revision fisica y copias de recepcion.
    DELETE FROM inv.RecepcionMercanciaRevisionUnidad WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.RecepcionMercanciaUnidad WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.UnidadIdentificador WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.UnidadSerializada WHERE EmpresaId=@EmpresaId;

    -- Recepciones de mercancia.
    DELETE FROM inv.RecepcionMercanciaLinea WHERE EmpresaId=@EmpresaId;
    DELETE FROM inv.RecepcionMercancia WHERE EmpresaId=@EmpresaId;

    -- Causaciones y sus comprobantes, solo cuando nacieron de estas compras.
    DELETE FROM comp.CausacionServicioLinea WHERE EmpresaId=@EmpresaId;
    DELETE FROM comp.CausacionServicio WHERE EmpresaId=@EmpresaId;
    DELETE l
    FROM cont.ComprobanteContableLinea l
    JOIN #Comprobantes c ON c.ComprobanteContableId=l.ComprobanteContableId
    WHERE l.EmpresaId=@EmpresaId;
    DELETE h
    FROM cont.ComprobanteContable h
    JOIN #Comprobantes c ON c.ComprobanteContableId=h.ComprobanteContableId
    WHERE h.EmpresaId=@EmpresaId;

    -- Documentos XML/manuales y sus detalles.
    DELETE FROM comp.DocumentoProveedorLineaTrazabilidad WHERE EmpresaId=@EmpresaId;
    DELETE FROM comp.DocumentoProveedorLineaUnidad WHERE EmpresaId=@EmpresaId;
    DELETE FROM comp.DocumentoProveedorLinea WHERE EmpresaId=@EmpresaId;
    DELETE FROM comp.DocumentoProveedor WHERE EmpresaId=@EmpresaId;

    -- Los lotes son datos operativos; los articulos y homologaciones se conservan.
    DELETE FROM inv.Lote WHERE EmpresaId=@EmpresaId;

    -- Los cierres ya se eliminaron. Se habilitan nuevamente los periodos para
    -- registrar entradas desde cero; los periodos BLOQUEADOS se respetan.
    UPDATE core.PeriodoInventario
    SET Estado='ABIERTO',CerradoEnUtc=NULL,CerradoPorUsuarioId=NULL,MotivoReapertura=NULL
    WHERE EmpresaId=@EmpresaId AND Estado IN('CERRADO','EN_CIERRE','REABIERTO');

    UPDATE core.PeriodoContable
    SET Estado='ABIERTO',CerradoEnUtc=NULL
    WHERE EmpresaId=@EmpresaId AND Estado IN('CERRADO','REABIERTO');

    INSERT audit.Evento
        (EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,Motivo,ValoresAnteriores,ValoresPosteriores,AplicacionOrigen)
    VALUES
        (@EmpresaId,NULL,'REINICIO_DEMO_COMPRAS_INVENTARIO','core.Empresa',CONVERT(nvarchar(100),@EmpresaId),
         N'Reinicio administrativo solicitado para comenzar compras e inventario desde cero.',@ResumenAntes,
         N'{"documentosProveedor":0,"recepciones":0,"causaciones":0,"movimientosKardex":0,"existenciaTotal":0,"valorInventario":0}',
         N'SCRIPT_ADMINISTRATIVO');

    ENABLE TRIGGER inv.TR_MovimientoInventario_Inmutable ON inv.MovimientoInventario;
    ENABLE TRIGGER inv.TR_MovimientoInventarioUnidad_Inmutable ON inv.MovimientoInventarioUnidad;
    ENABLE TRIGGER cont.TR_ComprobanteContable_Inmutable ON cont.ComprobanteContable;
    ENABLE TRIGGER cont.TR_ComprobanteContableLinea_Inmutable ON cont.ComprobanteContableLinea;

    COMMIT TRANSACTION;

    PRINT N'REINICIO COMPLETADO.';
    SELECT
        (SELECT COUNT(*) FROM comp.DocumentoProveedor WHERE EmpresaId=@EmpresaId) AS EntradasGuardadas,
        (SELECT COUNT(*) FROM inv.RecepcionMercancia WHERE EmpresaId=@EmpresaId) AS Recepciones,
        (SELECT COUNT(*) FROM inv.RecepcionMercanciaRevisionUnidad WHERE EmpresaId=@EmpresaId) AS RevisionesFisicas,
        (SELECT COUNT(*) FROM comp.CausacionServicio WHERE EmpresaId=@EmpresaId) AS CausacionesServicio,
        (SELECT COUNT(*) FROM inv.UnidadSerializada WHERE EmpresaId=@EmpresaId) AS UnidadesSerializadasInventario,
        (SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId) AS MovimientosKardex,
        (SELECT COUNT(*) FROM core.OutboxEvento WHERE EmpresaId=@EmpresaId) AS EventosOutbox,
        (SELECT COUNT(*) FROM core.AlertaOperacion WHERE EmpresaId=@EmpresaId) AS AlertasOperativas,
        (SELECT COUNT(*) FROM seg.AprobacionOperacion WHERE EmpresaId=@EmpresaId) AS AprobacionesOperativas,
        (SELECT COUNT(*) FROM core.PeriodoInventario WHERE EmpresaId=@EmpresaId AND Estado='ABIERTO') AS PeriodosInventarioAbiertos,
        (SELECT COUNT(*) FROM core.PeriodoContable WHERE EmpresaId=@EmpresaId AND Estado='ABIERTO') AS PeriodosContablesAbiertos,
        (SELECT COALESCE(SUM(Existencia),0) FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId) AS ExistenciaTotal,
        (SELECT COALESCE(SUM(ValorTotal),0) FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId) AS ValorInventario;
    DROP TABLE IF EXISTS #Comprobantes;
    DROP TABLE IF EXISTS #Causaciones;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;

    IF OBJECTPROPERTY(OBJECT_ID(N'inv.TR_MovimientoInventario_Inmutable'),N'ExecIsTriggerDisabled')=1
        ENABLE TRIGGER inv.TR_MovimientoInventario_Inmutable ON inv.MovimientoInventario;
    IF OBJECTPROPERTY(OBJECT_ID(N'inv.TR_MovimientoInventarioUnidad_Inmutable'),N'ExecIsTriggerDisabled')=1
        ENABLE TRIGGER inv.TR_MovimientoInventarioUnidad_Inmutable ON inv.MovimientoInventarioUnidad;
    IF OBJECTPROPERTY(OBJECT_ID(N'cont.TR_ComprobanteContable_Inmutable'),N'ExecIsTriggerDisabled')=1
        ENABLE TRIGGER cont.TR_ComprobanteContable_Inmutable ON cont.ComprobanteContable;
    IF OBJECTPROPERTY(OBJECT_ID(N'cont.TR_ComprobanteContableLinea_Inmutable'),N'ExecIsTriggerDisabled')=1
        ENABLE TRIGGER cont.TR_ComprobanteContableLinea_Inmutable ON cont.ComprobanteContableLinea;

    DROP TABLE IF EXISTS #Comprobantes;
    DROP TABLE IF EXISTS #Causaciones;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
    THROW;
END CATCH;
