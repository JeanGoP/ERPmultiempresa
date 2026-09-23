/*
 REINICIO TOTAL PARA PRUEBAS -- esquema ERP hasta 059.
 Sustituye el reinicio parcial de compras del archivo recibido.
 NO ES UNA MIGRACION. Nunca ejecutar automaticamente ni en Zeus.

 CONSERVA: exactamente la empresa MOTOCENTRO seleccionada, exactamente el
 superadministrador seleccionado y su credencial (misma contraseña).
 Conserva roles/permisos globales y SchemaMigration: son infraestructura.
 Recrea EmpresaConfiguracion con valores iniciales y deja UN evento de reinicio.
 BORRA EN TODAS LAS EMPRESAS: restantes usuarios/empresas, sesiones, auditoria
 historica, proveedores, articulos, marcas, bodegas, sucursales, periodos,
 cartera, comprobantes, inventario, configuraciones y colas Zeus.
 Incluye core.ZeusConexion (057): elimina las conexiones guardadas incluso de
 MOTOCENTRO; debera configurarlas nuevamente. No borra claves del servidor ni .env.
 No modifica comprobantes ni proveedores ya enviados a la base externa Zeus.
 No reinicia IDENTITY. Reimportar facturas puede duplicarlas en Zeus: use una
 base Zeus de pruebas limpia y configure de nuevo la integracion conscientemente.

 Antes de ejecutar: detener API, workers y accesos de escritura; hacer y verificar
 una copia de seguridad completa. El borrado confirmado SOLO se recupera con backup.
 1) Ejecutar primero SIN cambiar SOLO-VISTA-PREVIA. Revisar servidor, base,
    empresas, superadministradores y conteos.
 2) Poner el Codigo exacto de MOTOCENTRO y el UsuarioId del superadministrador.
 3) Poner el ServerName mostrado y la base exacta; confirmar respaldo/mantenimiento.
 4) Cambiar Confirmacion a BORRAR-TODO-EXCEPTO-MOTOCENTRO.
 No se elige TOP 1 ni se conserva un usuario ambiguo. No ejecutar dentro de otra
 transaccion. Si aparecen tablas nuevas desconocidas, se detiene para revisarlas.
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

DECLARE @BaseEsperada sysname = N'ERPMontelibano';
DECLARE @ServidorEsperado sysname = N'CAMBIAR-SERVIDOR';
DECLARE @EmpresaCodigo nvarchar(20) = N'CAMBIAR-CODIGO';
DECLARE @SuperAdminId bigint = NULL;
DECLARE @Confirmacion nvarchar(100) = N'SOLO-VISTA-PREVIA';
DECLARE @RespaldoVerificado bit = 0, @MantenimientoConfirmado bit = 0;
DECLARE @EmpresaId bigint, @Sql nvarchar(max), @Nombre nvarchar(517), @Predicado nvarchar(200);
DECLARE @BypassAnterior sql_variant = SESSION_CONTEXT(N'BypassRls');

IF @@TRANCOUNT<>0 THROW 52090,'Ejecute en una sesion sin transaccion abierta.',1;
IF OBJECT_ID(N'core.Empresa',N'U') IS NULL OR COL_LENGTH(N'seg.Usuario',N'EsSuperAdministrador') IS NULL
    THROW 52090,'Esta base no tiene el esquema ERP esperado.',1;

DROP TABLE IF EXISTS #ResetTablas;
DROP TABLE IF EXISTS #ResetTriggers;
DROP TABLE IF EXISTS #ResetFk;
CREATE TABLE #ResetTablas(Nombre nvarchar(257) PRIMARY KEY,Id int NULL,Predicado nvarchar(200) NOT NULL DEFAULT N'1=1',Antes bigint NULL,Borrar bigint NULL);
INSERT #ResetTablas(Nombre) VALUES
(N'audit.Evento'),
(N'comp.CausacionServicio'),
(N'comp.CausacionServicioLinea'),
(N'comp.DocumentoProveedor'),
(N'comp.DocumentoProveedorLinea'),
(N'comp.DocumentoProveedorLineaTrazabilidad'),
(N'comp.DocumentoProveedorLineaUnidad'),
(N'comp.HomologacionArticuloProveedor'),
(N'cont.ComprobanteContable'),
(N'cont.ComprobanteContableLinea'),
(N'cont.CuentaContable'),
(N'core.AlertaOperacion'),
(N'core.Consecutivo'),
(N'core.Empresa'),
(N'core.EmpresaConfiguracion'),
(N'core.EntregaIntegracion'),
(N'core.OutboxEvento'),
(N'core.PeriodoContable'),
(N'core.PeriodoInventario'),
(N'core.PoliticaParticionKardex'),
(N'core.SchemaMigration'),
(N'core.Sucursal'),
(N'core.ZeusBodegaCuenta'),
(N'core.ZeusConfiguracion'),
-- Conexion privada guardada en ERP: forma parte del reinicio, no es la base Zeus.
(N'core.ZeusConexion'),
(N'core.ZeusEnvio'),
(N'core.ZeusProveedorEnvio'),
(N'cost.AplicacionCostoAdquisicion'),
(N'cost.ConceptoCostoAdquisicion'),
(N'cost.DistribucionCosto'),
(N'cost.DistribucionCostoLinea'),
(N'cost.DistribucionCostoObjetivo'),
(N'cost.DocumentoCostoAdquisicion'),
(N'cost.LibroCosto'),
(N'cost.MovimientoCostoLibro'),
(N'cost.PoliticaValoracionGrupo'),
(N'cost.SaldoCostoLibroBodega'),
(N'cxp.DocumentoPorPagar'),
(N'cxp.EgresoBorrador'),
(N'cxp.Egreso'),
(N'cxp.EgresoLinea'),
(N'cxp.EgresoCuentaSucursal'),
(N'cxp.MovimientoProveedor'),
(N'inv.Articulo'),
(N'inv.ArticuloUnidad'),
(N'inv.BloqueoConteoFisico'),
(N'inv.Bodega'),
(N'inv.CatalogoMarcaDescripcion'),
(N'inv.CierrePeriodoInventario'),
(N'inv.CierrePeriodoInventarioSaldo'),
(N'inv.ConteoCaptura'),
(N'inv.ConteoFisico'),
(N'inv.ConteoFisicoLinea'),
(N'inv.DeterioroInventario'),
(N'inv.DevolucionProveedor'),
(N'inv.DevolucionProveedorLinea'),
(N'inv.DevolucionProveedorLineaUnidad'),
(N'inv.DevolucionVenta'),
(N'inv.DevolucionVentaLinea'),
(N'inv.DevolucionVentaLineaUnidad'),
(N'inv.GrupoInventario'),
(N'inv.Lote'),
(N'inv.Marca'),
(N'inv.MovimientoInventario'),
(N'inv.MovimientoInventarioArchivo'),
(N'inv.MovimientoInventarioUnidad'),
(N'inv.MovimientoOrigenInventario'),
(N'inv.OrigenInventario'),
(N'inv.RecepcionMercancia'),
(N'inv.RecepcionMercanciaLinea'),
(N'inv.RecepcionMercanciaRevisionUnidad'),
(N'inv.RecepcionMercanciaUnidad'),
(N'inv.ReconciliacionInventario'),
(N'inv.ReconciliacionInventarioDetalle'),
(N'inv.ReversionMovimientoInventario'),
(N'inv.SaldoArticuloBodega'),
(N'inv.SaldoArticuloLoteUbicacion'),
(N'inv.SaldoArticuloUbicacion'),
(N'inv.SaldoDeterioroInventario'),
(N'inv.SaldoOrigenBodega'),
(N'inv.SalidaExcepcionalNegativa'),
(N'inv.SolicitudSalidaSerializada'),
(N'inv.SolicitudSalidaSerializadaUnidad'),
(N'inv.Traslado'),
(N'inv.TrasladoLinea'),
(N'inv.TrasladoLineaUnidad'),
(N'inv.Ubicacion'),
(N'inv.UnidadIdentificador'),
(N'inv.UnidadMedida'),
(N'inv.UnidadSerializada'),
(N'seg.AprobacionOperacion'),
(N'seg.Permiso'),
(N'seg.Rol'),
(N'seg.RolPermiso'),
(N'seg.SesionApi'),
(N'seg.Usuario'),
(N'seg.UsuarioCredencial'),
(N'seg.UsuarioEmpresaPermiso'),
(N'seg.UsuarioEmpresaRol'),
(N'ter.Tercero');
UPDATE #ResetTablas SET Id=OBJECT_ID(Nombre,N'U');
-- No se incorporan tablas desconocidas automaticamente a un borrado global.
IF EXISTS(SELECT 1 FROM sys.tables t WHERE t.is_ms_shipped=0 AND NOT EXISTS(SELECT 1 FROM #ResetTablas p WHERE p.Id=t.object_id))
BEGIN
    SELECT SCHEMA_NAME(schema_id) Esquema,name TablaNoRevisada FROM sys.tables t
    WHERE is_ms_shipped=0 AND NOT EXISTS(SELECT 1 FROM #ResetTablas p WHERE p.Id=t.object_id);
    THROW 52090,'Hay tablas no revisadas. No se borro informacion.',1;
END;
-- Acepta tablas de migraciones opcionales ausentes, pero exige la infraestructura.
IF OBJECT_ID(N'seg.UsuarioCredencial',N'U') IS NULL OR OBJECT_ID(N'core.EmpresaConfiguracion',N'U') IS NULL
    THROW 52090,'Falta infraestructura requerida.',1;
DELETE #ResetTablas WHERE Id IS NULL;

BEGIN TRY
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
    SELECT CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) Servidor,DB_NAME() BaseActual;
    SELECT EmpresaId,Codigo,Nit,RazonSocial,Activa FROM core.Empresa ORDER BY EmpresaId;
    SELECT UsuarioId,Correo,NombreCompleto,Activo FROM seg.Usuario WHERE EsSuperAdministrador=1 ORDER BY UsuarioId;
    SELECT @EmpresaId=EmpresaId FROM core.Empresa
    WHERE Codigo=@EmpresaCodigo AND Activa=1
      AND UPPER(LTRIM(RTRIM(RazonSocial))) IN(N'MOTOCENTRO',N'MOTOCENTRO SA',N'MOTOCENTRO S.A.',N'MOTOCENTRO S.A.S.');

    UPDATE #ResetTablas SET Predicado=N'1=0' WHERE Nombre IN(N'core.SchemaMigration',N'seg.Rol',N'seg.Permiso',N'seg.RolPermiso');
    UPDATE #ResetTablas SET Predicado=N'EmpresaId<>@EmpresaId' WHERE Nombre=N'core.Empresa';
    UPDATE #ResetTablas SET Predicado=N'UsuarioId<>@SuperAdminId' WHERE Nombre IN(N'seg.Usuario',N'seg.UsuarioCredencial');

    IF @Confirmacion=N'SOLO-VISTA-PREVIA'
    BEGIN
        DECLARE vista CURSOR LOCAL FAST_FORWARD FOR SELECT Nombre,Predicado FROM #ResetTablas ORDER BY Nombre;
        OPEN vista;FETCH NEXT FROM vista INTO @Nombre,@Predicado;
        WHILE @@FETCH_STATUS=0
        BEGIN
            SET @Sql=N'UPDATE #ResetTablas SET Antes=(SELECT COUNT_BIG(*) FROM '+QUOTENAME(PARSENAME(@Nombre,2))+N'.'+QUOTENAME(PARSENAME(@Nombre,1))+N'),
              Borrar=(SELECT COUNT_BIG(*) FROM '+QUOTENAME(PARSENAME(@Nombre,2))+N'.'+QUOTENAME(PARSENAME(@Nombre,1))+N' WHERE '+@Predicado+N') WHERE Nombre=@Nombre;';
            EXEC sys.sp_executesql @Sql,N'@EmpresaId bigint,@SuperAdminId bigint,@Nombre nvarchar(517)',@EmpresaId,@SuperAdminId,@Nombre;
            FETCH NEXT FROM vista INTO @Nombre,@Predicado;
        END;
        CLOSE vista;DEALLOCATE vista;
        SELECT Nombre,Antes,Borrar FROM #ResetTablas ORDER BY Nombre;
        SELECT @EmpresaId EmpresaConservada,@SuperAdminId SuperAdminConservado,
          N'VISTA PREVIA. Si los IDs no estan seleccionados, los conteos de empresa/usuario no son definitivos. No se modificaron datos.' Aviso;
        EXEC sys.sp_set_session_context @key=N'BypassRls',@value=@BypassAnterior;
        RETURN;
    END;

    IF @Confirmacion<>N'BORRAR-TODO-EXCEPTO-MOTOCENTRO' OR @Confirmacion IS NULL
        THROW 52090,'Confirmacion de borrado incorrecta.',1;
    IF @BaseEsperada IS NULL OR DB_NAME()<>@BaseEsperada OR @ServidorEsperado IS NULL
       OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))<>@ServidorEsperado
        THROW 52090,'Servidor o base distintos del destino confirmado.',1;
    IF @RespaldoVerificado<>1 OR @MantenimientoConfirmado<>1
        THROW 52090,'Debe verificar respaldo y detener API, workers y escrituras.',1;
    IF @EmpresaId IS NULL
        THROW 52090,'Seleccione por codigo una empresa activa MOTOCENTRO. No se borro informacion.',1;
    IF NOT EXISTS(SELECT 1 FROM seg.Usuario u JOIN seg.UsuarioCredencial c ON c.UsuarioId=u.UsuarioId
                  WHERE u.UsuarioId=@SuperAdminId AND u.EsSuperAdministrador=1 AND u.Activo=1
                  AND (c.BloqueadoHastaUtc IS NULL OR c.BloqueadoHastaUtc<=SYSUTCDATETIME()))
        THROW 52090,'Seleccione un superadministrador activo, con credencial y sin bloqueo.',1;
    IF EXISTS(SELECT 1 FROM sys.foreign_keys WHERE is_disabled=1 OR is_not_trusted=1)
        THROW 52090,'Hay claves foraneas deshabilitadas o sin verificar. Corregir antes del reinicio.',1;

    BEGIN TRANSACTION;
    -- Bloqueo exclusivo por tabla durante TODO el reinicio. No usar con API activa.
    DECLARE tablas CURSOR LOCAL FAST_FORWARD FOR SELECT Nombre,Predicado FROM #ResetTablas ORDER BY Nombre;
    OPEN tablas;FETCH NEXT FROM tablas INTO @Nombre,@Predicado;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @Sql=N'UPDATE #ResetTablas SET Antes=(SELECT COUNT_BIG(*) FROM '+QUOTENAME(PARSENAME(@Nombre,2))+N'.'+QUOTENAME(PARSENAME(@Nombre,1))+N' WITH(TABLOCKX,HOLDLOCK)) WHERE Nombre=@Nombre;';
        EXEC sys.sp_executesql @Sql,N'@Nombre nvarchar(517)',@Nombre;
        FETCH NEXT FROM tablas INTO @Nombre,@Predicado;
    END;
    CLOSE tablas;
    -- Revalidacion bajo bloqueo: nadie puede cambiar los registros conservados.
    IF NOT EXISTS(SELECT 1 FROM core.Empresa WHERE EmpresaId=@EmpresaId AND Codigo=@EmpresaCodigo AND Activa=1)
       OR NOT EXISTS(SELECT 1 FROM seg.Usuario WHERE UsuarioId=@SuperAdminId AND Activo=1 AND EsSuperAdministrador=1)
        THROW 52090,'La empresa o el usuario cambiaron durante la confirmacion.',1;

    SELECT t.object_id,QUOTENAME(OBJECT_SCHEMA_NAME(t.object_id))+N'.'+QUOTENAME(t.name) Nombre,
       QUOTENAME(OBJECT_SCHEMA_NAME(t.parent_id))+N'.'+QUOTENAME(OBJECT_NAME(t.parent_id)) Tabla
    INTO #ResetTriggers FROM sys.triggers t JOIN #ResetTablas p ON p.Id=t.parent_id WHERE t.is_disabled=0;
    SELECT f.object_id,QUOTENAME(f.name) Nombre,
       QUOTENAME(OBJECT_SCHEMA_NAME(f.parent_object_id))+N'.'+QUOTENAME(OBJECT_NAME(f.parent_object_id)) Tabla
    INTO #ResetFk FROM sys.foreign_keys f;

    SET @Sql=N'';
    SELECT @Sql=@Sql+N'DISABLE TRIGGER '+Nombre+N' ON '+Tabla+N';' FROM #ResetTriggers;
    EXEC sys.sp_executesql @Sql;
    SET @Sql=N'';
    SELECT @Sql=@Sql+N'ALTER TABLE '+Tabla+N' NOCHECK CONSTRAINT '+Nombre+N';' FROM #ResetFk;
    EXEC sys.sp_executesql @Sql;

    OPEN tablas;FETCH NEXT FROM tablas INTO @Nombre,@Predicado;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @Sql=N'DELETE FROM '+QUOTENAME(PARSENAME(@Nombre,2))+N'.'+QUOTENAME(PARSENAME(@Nombre,1))+N' WHERE '+@Predicado+N';
          UPDATE #ResetTablas SET Borrar=@@ROWCOUNT WHERE Nombre=@Nombre;';
        EXEC sys.sp_executesql @Sql,N'@EmpresaId bigint,@SuperAdminId bigint,@Nombre nvarchar(517)',@EmpresaId,@SuperAdminId,@Nombre;
        FETCH NEXT FROM tablas INTO @Nombre,@Predicado;
    END;
    CLOSE tablas;DEALLOCATE tablas;

    -- Comprobar todos los objetivos, no solo documentos/proveedores.
    DECLARE comprobar CURSOR LOCAL FAST_FORWARD FOR SELECT Nombre,Predicado FROM #ResetTablas;
    OPEN comprobar;FETCH NEXT FROM comprobar INTO @Nombre,@Predicado;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @Sql=N'IF EXISTS(SELECT 1 FROM '+QUOTENAME(PARSENAME(@Nombre,2))+N'.'+QUOTENAME(PARSENAME(@Nombre,1))+N' WHERE '+@Predicado+N') THROW 52090,''Quedaron datos por borrar. Se revierte el reinicio.'',1;';
        EXEC sys.sp_executesql @Sql,N'@EmpresaId bigint,@SuperAdminId bigint',@EmpresaId,@SuperAdminId;
        FETCH NEXT FROM comprobar INTO @Nombre,@Predicado;
    END;
    CLOSE comprobar;DEALLOCATE comprobar;
    IF (SELECT COUNT(*) FROM core.Empresa)<>1 OR (SELECT COUNT(*) FROM seg.Usuario)<>1
       OR (SELECT COUNT(*) FROM seg.UsuarioCredencial)<>1
        THROW 52090,'No se conservaron exactamente una empresa y un usuario con credencial.',1;

    INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);
    DECLARE @Resumen nvarchar(max)=(SELECT Nombre,Antes,Borrar FROM #ResetTablas ORDER BY Nombre FOR JSON PATH);
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,Motivo,ValoresAnteriores,AplicacionOrigen)
    VALUES(@EmpresaId,@SuperAdminId,'REINICIO_TOTAL_PRUEBAS','core.Empresa',CONVERT(nvarchar(100),@EmpresaId),
      N'Reinicio total confirmado. Se conserva MOTOCENTRO y un superadministrador. Zeus externo no modificado.',@Resumen,N'SCRIPT_ADMINISTRATIVO');

    SET @Sql=N'';
    SELECT @Sql=@Sql+N'ALTER TABLE '+Tabla+N' WITH CHECK CHECK CONSTRAINT '+Nombre+N';' FROM #ResetFk;
    EXEC sys.sp_executesql @Sql;
    SET @Sql=N'';
    SELECT @Sql=@Sql+N'ENABLE TRIGGER '+Nombre+N' ON '+Tabla+N';' FROM #ResetTriggers;
    EXEC sys.sp_executesql @Sql;
    IF EXISTS(SELECT 1 FROM sys.foreign_keys WHERE is_disabled=1 OR is_not_trusted=1)
        THROW 52090,'No se restauraron todas las relaciones.',1;
    IF EXISTS(SELECT 1 FROM #ResetTriggers r JOIN sys.triggers t ON t.object_id=r.object_id WHERE t.is_disabled=1)
        THROW 52090,'No se restauraron todos los triggers.',1;
    COMMIT;
    SELECT Nombre,Antes,Borrar FROM #ResetTablas ORDER BY Nombre;
    SELECT EmpresaId,Codigo,Nit,RazonSocial FROM core.Empresa;
    SELECT UsuarioId,Correo,NombreCompleto FROM seg.Usuario;
    PRINT N'REINICIO COMPLETADO. Inicie sesion de nuevo. Configure bodegas, sucursales, periodos y Zeus antes de operar.';
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=@BypassAnterior;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK;
    -- DDL transaccional: rollback restaura los triggers y FK al estado previo.
    -- No habilitar indiscriminadamente objetos que antes estaban deshabilitados.
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=@BypassAnterior;
    THROW;
END CATCH;
