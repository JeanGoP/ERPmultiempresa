SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='037_production_operations')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;

    ALTER TABLE core.OutboxEvento ADD BloqueadoHastaUtc datetime2(7) NULL,BloqueadoPor nvarchar(100) NULL,DescartadoEnUtc datetime2(7) NULL;

    CREATE TABLE core.EntregaIntegracion
    (
        EntregaIntegracionId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        OutboxEventoId bigint NOT NULL,
        EventoGuid uniqueidentifier NOT NULL,
        TipoEvento nvarchar(120) NOT NULL,
        Destino nvarchar(100) NOT NULL,
        Respuesta nvarchar(1000) NULL,
        EntregadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_EntregaIntegracion_Fecha DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_EntregaIntegracion PRIMARY KEY CLUSTERED(EntregaIntegracionId),
        CONSTRAINT UQ_EntregaIntegracion_Outbox UNIQUE(OutboxEventoId,Destino),
        CONSTRAINT FK_EntregaIntegracion_Empresa FOREIGN KEY(EmpresaId) REFERENCES core.Empresa(EmpresaId),
        CONSTRAINT FK_EntregaIntegracion_Outbox FOREIGN KEY(OutboxEventoId) REFERENCES core.OutboxEvento(OutboxEventoId)
    );
    CREATE INDEX IX_EntregaIntegracion_EmpresaFecha ON core.EntregaIntegracion(EmpresaId,EntregadoEnUtc DESC) INCLUDE(TipoEvento,Destino);

    CREATE TABLE core.AlertaOperacion
    (
        AlertaOperacionId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        Severidad varchar(10) NOT NULL,
        Codigo varchar(50) NOT NULL,
        Mensaje nvarchar(1000) NOT NULL,
        Entidad nvarchar(100) NULL,
        EntidadId nvarchar(100) NULL,
        CreadaEnUtc datetime2(7) NOT NULL CONSTRAINT DF_AlertaOperacion_Fecha DEFAULT SYSUTCDATETIME(),
        ResueltaEnUtc datetime2(7) NULL,
        CONSTRAINT PK_AlertaOperacion PRIMARY KEY CLUSTERED(AlertaOperacionId),
        CONSTRAINT FK_AlertaOperacion_Empresa FOREIGN KEY(EmpresaId) REFERENCES core.Empresa(EmpresaId),
        CONSTRAINT CK_AlertaOperacion_Severidad CHECK(Severidad IN('INFO','WARNING','CRITICAL'))
    );
    CREATE INDEX IX_AlertaOperacion_Activa ON core.AlertaOperacion(EmpresaId,ResueltaEnUtc,Severidad,CreadaEnUtc DESC) WHERE ResueltaEnUtc IS NULL;

    CREATE TABLE inv.MovimientoInventarioArchivo
    (
        MovimientoInventarioId bigint NOT NULL,
        EmpresaId bigint NOT NULL,
        PeriodoParticion int NOT NULL,
        FechaContable date NOT NULL,
        FechaMovimiento datetime2(7) NOT NULL,
        BodegaId bigint NOT NULL,
        ArticuloId bigint NOT NULL,
        PeriodoInventarioId bigint NOT NULL,
        TipoMovimiento varchar(30) NOT NULL,
        TipoDocumentoOrigen varchar(40) NOT NULL,
        DocumentoOrigenId bigint NOT NULL,
        NumeroDocumento nvarchar(50) NOT NULL,
        CantidadEntrada decimal(20,6) NOT NULL,
        CantidadSalida decimal(20,6) NOT NULL,
        CostoUnitarioMovimiento decimal(20,8) NOT NULL,
        ValorMovimiento decimal(20,4) NOT NULL,
        ExistenciaPosterior decimal(20,6) NOT NULL,
        ValorTotalPosterior decimal(20,4) NOT NULL,
        ArchivadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_MovimientoArchivo_Fecha DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_MovimientoInventarioArchivo PRIMARY KEY CLUSTERED(EmpresaId,PeriodoParticion,MovimientoInventarioId),
        CONSTRAINT FK_MovimientoInventarioArchivo_Empresa FOREIGN KEY(EmpresaId) REFERENCES core.Empresa(EmpresaId)
    );
    CREATE INDEX IX_MovimientoArchivo_Consulta ON inv.MovimientoInventarioArchivo(EmpresaId,ArticuloId,BodegaId,FechaContable,MovimientoInventarioId);

    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.EntregaIntegracion;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.EntregaIntegracion AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.AlertaOperacion;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.AlertaOperacion AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.MovimientoInventarioArchivo;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.MovimientoInventarioArchivo AFTER INSERT;');

    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('037_production_operations',N'Consumo Outbox, entregas, alertas y archivo verificable para preparacion productiva');
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO

CREATE OR ALTER PROCEDURE core.usp_ReclamarOutbox
    @Trabajador nvarchar(100),@TamanoLote int=25,@SegundosBloqueo int=60,@EmpresaId bigint=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @TamanoLote NOT BETWEEN 1 AND 200 THROW 51990,'El tamano del lote Outbox debe estar entre 1 y 200.',1;
    ;WITH pendientes AS
    (
        SELECT TOP(@TamanoLote) * FROM core.OutboxEvento WITH(UPDLOCK,READPAST,ROWLOCK)
        WHERE ProcesadoEnUtc IS NULL AND DescartadoEnUtc IS NULL AND DisponibleEnUtc<=SYSUTCDATETIME()
          AND (@EmpresaId IS NULL OR EmpresaId=@EmpresaId)
          AND (BloqueadoHastaUtc IS NULL OR BloqueadoHastaUtc<SYSUTCDATETIME())
        ORDER BY OutboxEventoId
    )
    UPDATE pendientes SET BloqueadoPor=@Trabajador,BloqueadoHastaUtc=DATEADD(SECOND,@SegundosBloqueo,SYSUTCDATETIME()),Intentos=Intentos+1
    OUTPUT inserted.OutboxEventoId,inserted.EmpresaId,inserted.EventoGuid,inserted.TipoEvento,inserted.TipoAgregado,inserted.AgregadoId,inserted.Payload,inserted.Intentos;
END;
GO

CREATE OR ALTER PROCEDURE core.usp_ConfirmarOutbox
    @OutboxEventoId bigint,@Trabajador nvarchar(100),@Destino nvarchar(100),@Respuesta nvarchar(1000)=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON; BEGIN TRANSACTION;
    DECLARE @EmpresaId bigint,@EventoGuid uniqueidentifier,@TipoEvento nvarchar(120);
    SELECT @EmpresaId=EmpresaId,@EventoGuid=EventoGuid,@TipoEvento=TipoEvento FROM core.OutboxEvento WITH(UPDLOCK,HOLDLOCK)
    WHERE OutboxEventoId=@OutboxEventoId AND ProcesadoEnUtc IS NULL AND BloqueadoPor=@Trabajador;
    IF @EmpresaId IS NULL
    BEGIN
        IF EXISTS(SELECT 1 FROM core.OutboxEvento WHERE OutboxEventoId=@OutboxEventoId AND ProcesadoEnUtc IS NOT NULL) BEGIN COMMIT; RETURN; END;
        THROW 51991,'El evento Outbox no esta reclamado por el trabajador.',1;
    END;
    IF NOT EXISTS(SELECT 1 FROM core.EntregaIntegracion WHERE OutboxEventoId=@OutboxEventoId AND Destino=@Destino)
        INSERT core.EntregaIntegracion(EmpresaId,OutboxEventoId,EventoGuid,TipoEvento,Destino,Respuesta)
        VALUES(@EmpresaId,@OutboxEventoId,@EventoGuid,@TipoEvento,@Destino,@Respuesta);
    UPDATE core.OutboxEvento SET ProcesadoEnUtc=SYSUTCDATETIME(),BloqueadoHastaUtc=NULL,BloqueadoPor=NULL,UltimoError=NULL WHERE OutboxEventoId=@OutboxEventoId;
    COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE core.usp_FallarOutbox
    @OutboxEventoId bigint,@Trabajador nvarchar(100),@Error nvarchar(2000),@MaximoIntentos int=8
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON; BEGIN TRANSACTION;
    DECLARE @EmpresaId bigint,@Intentos int,@TipoEvento nvarchar(120);
    SELECT @EmpresaId=EmpresaId,@Intentos=Intentos,@TipoEvento=TipoEvento FROM core.OutboxEvento WITH(UPDLOCK,HOLDLOCK)
    WHERE OutboxEventoId=@OutboxEventoId AND ProcesadoEnUtc IS NULL AND BloqueadoPor=@Trabajador;
    IF @EmpresaId IS NULL THROW 51992,'El evento Outbox no esta reclamado por el trabajador.',1;
    UPDATE core.OutboxEvento SET UltimoError=LEFT(@Error,2000),BloqueadoHastaUtc=NULL,BloqueadoPor=NULL,
        DisponibleEnUtc=DATEADD(SECOND,CASE WHEN @Intentos>=7 THEN 300 ELSE POWER(2,@Intentos) END,SYSUTCDATETIME()),
        DescartadoEnUtc=CASE WHEN @Intentos>=@MaximoIntentos THEN SYSUTCDATETIME() ELSE NULL END
    WHERE OutboxEventoId=@OutboxEventoId;
    IF @Intentos>=@MaximoIntentos AND NOT EXISTS(SELECT 1 FROM core.AlertaOperacion WHERE EmpresaId=@EmpresaId AND Codigo='OUTBOX_DESCARTADO' AND EntidadId=CONVERT(nvarchar(100),@OutboxEventoId) AND ResueltaEnUtc IS NULL)
        INSERT core.AlertaOperacion(EmpresaId,Severidad,Codigo,Mensaje,Entidad,EntidadId)
        VALUES(@EmpresaId,'CRITICAL','OUTBOX_DESCARTADO',CONCAT(N'Evento ',@TipoEvento,N' agotó ',@Intentos,N' intentos: ',LEFT(@Error,800)),N'core.OutboxEvento',CONVERT(nvarchar(100),@OutboxEventoId));
    COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE core.usp_ReintentarOutbox @EmpresaId bigint,@OutboxEventoId bigint
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE core.OutboxEvento SET DescartadoEnUtc=NULL,DisponibleEnUtc=SYSUTCDATETIME(),BloqueadoHastaUtc=NULL,BloqueadoPor=NULL,UltimoError=NULL
    WHERE EmpresaId=@EmpresaId AND OutboxEventoId=@OutboxEventoId AND ProcesadoEnUtc IS NULL;
    IF @@ROWCOUNT=0 THROW 51993,'El evento no existe, ya fue procesado o pertenece a otra empresa.',1;
    UPDATE core.AlertaOperacion SET ResueltaEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@EmpresaId AND Codigo='OUTBOX_DESCARTADO' AND EntidadId=CONVERT(nvarchar(100),@OutboxEventoId) AND ResueltaEnUtc IS NULL;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_ArchivarKardexCerrado @EmpresaId bigint,@TamanoLote int=10000
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET CONCAT_NULL_YIELDS_NULL ON; SET ARITHABORT ON; SET NUMERIC_ROUNDABORT OFF;
    DECLARE @Meses int,@Habilitado bit;
    SELECT @Meses=MesesEnLinea,@Habilitado=ArchivadoHabilitado FROM core.PoliticaParticionKardex WHERE EmpresaId=@EmpresaId;
    IF @Habilitado<>1 THROW 51994,'El archivado no esta habilitado para la empresa.',1;
    IF @TamanoLote NOT BETWEEN 1 AND 100000 THROW 51995,'El lote de archivo debe estar entre 1 y 100000.',1;
    DECLARE @Corte date=EOMONTH(DATEADD(MONTH,-@Meses,CONVERT(date,SYSUTCDATETIME())));
    INSERT inv.MovimientoInventarioArchivo(MovimientoInventarioId,EmpresaId,PeriodoParticion,FechaContable,FechaMovimiento,BodegaId,ArticuloId,PeriodoInventarioId,TipoMovimiento,TipoDocumentoOrigen,DocumentoOrigenId,NumeroDocumento,CantidadEntrada,CantidadSalida,CostoUnitarioMovimiento,ValorMovimiento,ExistenciaPosterior,ValorTotalPosterior)
    SELECT TOP(@TamanoLote) m.MovimientoInventarioId,m.EmpresaId,m.PeriodoParticion,m.FechaContable,m.FechaMovimiento,m.BodegaId,m.ArticuloId,m.PeriodoInventarioId,m.TipoMovimiento,m.TipoDocumentoOrigen,m.DocumentoOrigenId,m.NumeroDocumento,m.CantidadEntrada,m.CantidadSalida,m.CostoUnitarioMovimiento,m.ValorMovimiento,m.ExistenciaPosterior,m.ValorTotalPosterior
    FROM inv.MovimientoInventario m JOIN core.PeriodoInventario p ON p.EmpresaId=m.EmpresaId AND p.PeriodoInventarioId=m.PeriodoInventarioId
    WHERE m.EmpresaId=@EmpresaId AND p.Estado='CERRADO' AND p.FechaFin<@Corte
      AND NOT EXISTS(SELECT 1 FROM inv.MovimientoInventarioArchivo a WHERE a.EmpresaId=m.EmpresaId AND a.PeriodoParticion=m.PeriodoParticion AND a.MovimientoInventarioId=m.MovimientoInventarioId)
    ORDER BY m.MovimientoInventarioId;
    DECLARE @Copiados int=@@ROWCOUNT;
    UPDATE core.PoliticaParticionKardex SET UltimaEvaluacionEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@EmpresaId;
    SELECT @Copiados MovimientosCopiados,@Corte FechaCorte,(SELECT COUNT_BIG(*) FROM inv.MovimientoInventarioArchivo WHERE EmpresaId=@EmpresaId) TotalArchivado,CAST(0 AS bit) OrigenEliminado;
END;
GO
