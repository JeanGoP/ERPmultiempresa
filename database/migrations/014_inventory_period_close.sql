SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='014_inventory_period_close')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
    CREATE TABLE inv.CierrePeriodoInventario
    (
        CierrePeriodoInventarioId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        PeriodoInventarioId bigint NOT NULL,
        VersionCierre int NOT NULL,
        TotalReferencias bigint NOT NULL,
        TotalExistencia decimal(28,6) NOT NULL,
        TotalValor decimal(28,4) NOT NULL,
        CerradoPorUsuarioId bigint NULL,
        CerradoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_CierrePeriodo_Fecha DEFAULT SYSUTCDATETIME(),
        Estado varchar(12) NOT NULL CONSTRAINT DF_CierrePeriodo_Estado DEFAULT 'VIGENTE',
        CONSTRAINT PK_CierrePeriodoInventario PRIMARY KEY CLUSTERED(CierrePeriodoInventarioId),
        CONSTRAINT UQ_CierrePeriodoInventario_EmpresaId UNIQUE(EmpresaId,CierrePeriodoInventarioId),
        CONSTRAINT UQ_CierrePeriodoInventario_Version UNIQUE(EmpresaId,PeriodoInventarioId,VersionCierre),
        CONSTRAINT FK_CierrePeriodoInventario_Periodo FOREIGN KEY(EmpresaId,PeriodoInventarioId) REFERENCES core.PeriodoInventario(EmpresaId,PeriodoInventarioId),
        CONSTRAINT FK_CierrePeriodoInventario_Usuario FOREIGN KEY(CerradoPorUsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_CierrePeriodoInventario_Estado CHECK(Estado IN('VIGENTE','REABIERTO'))
    );
    CREATE TABLE inv.CierrePeriodoInventarioSaldo
    (
        CierrePeriodoInventarioSaldoId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        CierrePeriodoInventarioId bigint NOT NULL,
        BodegaId bigint NOT NULL,
        ArticuloId bigint NOT NULL,
        Existencia decimal(20,6) NOT NULL,
        CostoPromedio decimal(20,8) NOT NULL,
        ValorTotal decimal(20,4) NOT NULL,
        UltimoMovimientoId bigint NULL,
        CONSTRAINT PK_CierrePeriodoInventarioSaldo PRIMARY KEY CLUSTERED(CierrePeriodoInventarioSaldoId),
        CONSTRAINT UQ_CierrePeriodoInventarioSaldo UNIQUE(EmpresaId,CierrePeriodoInventarioId,BodegaId,ArticuloId),
        CONSTRAINT FK_CierrePeriodoInventarioSaldo_Cierre FOREIGN KEY(EmpresaId,CierrePeriodoInventarioId) REFERENCES inv.CierrePeriodoInventario(EmpresaId,CierrePeriodoInventarioId),
        CONSTRAINT FK_CierrePeriodoInventarioSaldo_Bodega FOREIGN KEY(EmpresaId,BodegaId) REFERENCES inv.Bodega(EmpresaId,BodegaId),
        CONSTRAINT FK_CierrePeriodoInventarioSaldo_Articulo FOREIGN KEY(EmpresaId,ArticuloId) REFERENCES inv.Articulo(EmpresaId,ArticuloId),
        CONSTRAINT FK_CierrePeriodoInventarioSaldo_Movimiento FOREIGN KEY(EmpresaId,UltimoMovimientoId) REFERENCES inv.MovimientoInventario(EmpresaId,MovimientoInventarioId)
    );
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.CierrePeriodoInventario;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.CierrePeriodoInventario AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.CierrePeriodoInventario AFTER UPDATE;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.CierrePeriodoInventarioSaldo;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.CierrePeriodoInventarioSaldo AFTER INSERT;');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('014_inventory_period_close',N'Cierre, fotografía y reapertura auditada del periodo de inventario');
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
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
    BEGIN
        COMMIT;
        SELECT @PeriodoInventarioId PeriodoInventarioId,@Estado Estado,(SELECT MAX(VersionCierre) FROM inv.CierrePeriodoInventario WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoInventarioId) VersionCierre,CAST(1 AS bit) YaExistia;
        RETURN;
    END;
    IF @Estado NOT IN('ABIERTO','REABIERTO') THROW 51871,'El periodo no está disponible para cierre.',1;
    UPDATE core.PeriodoInventario SET Estado='EN_CIERRE' WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoInventarioId;
    IF EXISTS(SELECT 1 FROM inv.RecepcionMercancia WHERE EmpresaId=@EmpresaId AND FechaContable BETWEEN @Inicio AND @Fin AND Estado IN('BORRADOR','VALIDADA'))
        THROW 51872,'Existen recepciones pendientes en el periodo.',1;
    IF EXISTS(SELECT 1 FROM inv.DevolucionProveedor WHERE EmpresaId=@EmpresaId AND FechaContable BETWEEN @Inicio AND @Fin AND Estado IN('BORRADOR','VALIDADA'))
        THROW 51873,'Existen devoluciones pendientes en el periodo.',1;
    IF EXISTS(SELECT 1 FROM inv.ConteoFisico WHERE EmpresaId=@EmpresaId AND CONVERT(date,FechaCorte) BETWEEN @Inicio AND @Fin AND Estado IN('APROBADO'))
        THROW 51874,'Existen conteos aprobados sin aplicar en el periodo.',1;
    IF EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND (Existencia<0 OR ValorTotal<0 OR CostoPromedio<0 OR ABS(ValorTotal-CAST(Existencia*CostoPromedio AS decimal(20,4)))>0.01))
        THROW 51875,'Los saldos contienen negativos o diferencias de valoración.',1;

    DECLARE @Version int=COALESCE((SELECT MAX(VersionCierre) FROM inv.CierrePeriodoInventario WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoInventarioId),0)+1;
    DECLARE @CierreId bigint;
    INSERT inv.CierrePeriodoInventario(EmpresaId,PeriodoInventarioId,VersionCierre,TotalReferencias,TotalExistencia,TotalValor,CerradoPorUsuarioId)
    SELECT @EmpresaId,@PeriodoInventarioId,@Version,COUNT(*),COALESCE(SUM(CAST(Existencia AS decimal(28,6))),0),COALESCE(SUM(CAST(ValorTotal AS decimal(28,4))),0),@UsuarioId
    FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId;
    SET @CierreId=SCOPE_IDENTITY();
    INSERT inv.CierrePeriodoInventarioSaldo(EmpresaId,CierrePeriodoInventarioId,BodegaId,ArticuloId,Existencia,CostoPromedio,ValorTotal,UltimoMovimientoId)
    SELECT @EmpresaId,@CierreId,BodegaId,ArticuloId,Existencia,CostoPromedio,ValorTotal,UltimoMovimientoId FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId;
    UPDATE core.PeriodoInventario SET Estado='CERRADO',CerradoEnUtc=SYSUTCDATETIME(),CerradoPorUsuarioId=@UsuarioId,MotivoReapertura=NULL
    WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoInventarioId;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresPosteriores,AplicacionOrigen)
    VALUES(@EmpresaId,@UsuarioId,'PERIODO_INVENTARIO_CERRADO','core.PeriodoInventario',CONVERT(nvarchar(100),@PeriodoInventarioId),@Codigo,CONCAT(N'{"version":',@Version,N',"cierreId":',@CierreId,N'}'),'INVENTARIO');
    COMMIT;
    SELECT @PeriodoInventarioId PeriodoInventarioId,CAST('CERRADO' AS varchar(15)) Estado,@Version VersionCierre,CAST(0 AS bit) YaExistia;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_ReabrirPeriodoInventario
    @EmpresaId bigint,@PeriodoInventarioId bigint,@Motivo nvarchar(500),@UsuarioId bigint=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF NULLIF(LTRIM(RTRIM(@Motivo)),N'') IS NULL OR LEN(LTRIM(RTRIM(@Motivo)))<10 THROW 51880,'La reapertura requiere un motivo de al menos 10 caracteres.',1;
    BEGIN TRANSACTION;
    DECLARE @Estado varchar(15),@Codigo char(7);
    SELECT @Estado=Estado,@Codigo=Codigo FROM core.PeriodoInventario WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoInventarioId;
    IF @Estado IS NULL THROW 51881,'El periodo no existe o no pertenece a la empresa.',1;
    IF @Estado<>'CERRADO' THROW 51882,'Solo un periodo cerrado puede reabrirse.',1;
    UPDATE inv.CierrePeriodoInventario SET Estado='REABIERTO' WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoInventarioId AND Estado='VIGENTE';
    UPDATE core.PeriodoInventario SET Estado='REABIERTO',MotivoReapertura=@Motivo,CerradoEnUtc=NULL,CerradoPorUsuarioId=NULL WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoInventarioId;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresPosteriores,AplicacionOrigen)
    VALUES(@EmpresaId,@UsuarioId,'PERIODO_INVENTARIO_REABIERTO','core.PeriodoInventario',CONVERT(nvarchar(100),@PeriodoInventarioId),@Codigo,CONCAT(N'{"motivo":"',STRING_ESCAPE(@Motivo,'json'),N'"}'),'INVENTARIO');
    COMMIT;
    SELECT @PeriodoInventarioId PeriodoInventarioId,CAST('REABIERTO' AS varchar(15)) Estado;
END;
GO
