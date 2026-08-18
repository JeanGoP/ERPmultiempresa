SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='025_physical_count_freeze')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
    CREATE UNIQUE INDEX UX_ConteoFisicoLinea_Dimension ON inv.ConteoFisicoLinea(EmpresaId,ConteoFisicoId,ArticuloId,UbicacionId,LoteId);
    CREATE TABLE inv.BloqueoConteoFisico
    (
        BloqueoConteoFisicoId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        ConteoFisicoId bigint NOT NULL,
        BodegaId bigint NOT NULL,
        ArticuloId bigint NOT NULL,
        UbicacionId bigint NULL,
        LoteId bigint NULL,
        Activo bit NOT NULL CONSTRAINT DF_BloqueoConteo_Activo DEFAULT 1,
        CreadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_BloqueoConteo_Fecha DEFAULT SYSUTCDATETIME(),
        LiberadoEnUtc datetime2(7) NULL,
        CONSTRAINT PK_BloqueoConteoFisico PRIMARY KEY CLUSTERED(BloqueoConteoFisicoId),
        CONSTRAINT UQ_BloqueoConteoFisico UNIQUE(EmpresaId,ConteoFisicoId,ArticuloId,UbicacionId,LoteId),
        CONSTRAINT FK_BloqueoConteo_Conteo FOREIGN KEY(EmpresaId,ConteoFisicoId) REFERENCES inv.ConteoFisico(EmpresaId,ConteoFisicoId),
        CONSTRAINT FK_BloqueoConteo_Bodega FOREIGN KEY(EmpresaId,BodegaId) REFERENCES inv.Bodega(EmpresaId,BodegaId),
        CONSTRAINT FK_BloqueoConteo_Articulo FOREIGN KEY(EmpresaId,ArticuloId) REFERENCES inv.Articulo(EmpresaId,ArticuloId),
        CONSTRAINT FK_BloqueoConteo_Ubicacion FOREIGN KEY(EmpresaId,UbicacionId) REFERENCES inv.Ubicacion(EmpresaId,UbicacionId),
        CONSTRAINT FK_BloqueoConteo_Lote FOREIGN KEY(EmpresaId,LoteId) REFERENCES inv.Lote(EmpresaId,LoteId)
    );
    CREATE INDEX IX_BloqueoConteoFisico_Activo ON inv.BloqueoConteoFisico(EmpresaId,BodegaId,ArticuloId,Activo) INCLUDE(UbicacionId,LoteId,ConteoFisicoId) WHERE Activo=1;
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.BloqueoConteoFisico;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.BloqueoConteoFisico AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.BloqueoConteoFisico AFTER UPDATE;');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('025_physical_count_freeze',N'Ciclo formal de conteo físico con congelación lógica, capturas, revisión y aprobación');
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO

CREATE OR ALTER TRIGGER inv.TR_MovimientoInventario_BloqueoConteo ON inv.MovimientoInventario AFTER INSERT AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS
    (
        SELECT 1 FROM inserted i JOIN inv.BloqueoConteoFisico b ON b.EmpresaId=i.EmpresaId AND b.BodegaId=i.BodegaId AND b.ArticuloId=i.ArticuloId AND b.Activo=1
          AND (b.UbicacionId IS NULL OR b.UbicacionId=i.UbicacionId) AND (b.LoteId IS NULL OR b.LoteId=i.LoteId)
        WHERE i.TipoDocumentoOrigen<>'CONTEO_FISICO'
    ) THROW 51990,'El artículo está congelado por un conteo físico activo.',1;
END;
GO

CREATE OR ALTER TRIGGER inv.TR_ConteoFisico_LiberarBloqueo ON inv.ConteoFisico AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE b SET Activo=0,LiberadoEnUtc=SYSUTCDATETIME()
    FROM inv.BloqueoConteoFisico b JOIN inserted i ON i.EmpresaId=b.EmpresaId AND i.ConteoFisicoId=b.ConteoFisicoId
    JOIN deleted d ON d.EmpresaId=i.EmpresaId AND d.ConteoFisicoId=i.ConteoFisicoId
    WHERE i.Estado IN('APLICADO','CANCELADO') AND d.Estado<>i.Estado AND b.Activo=1;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_IniciarConteoFisico @EmpresaId bigint,@ConteoFisicoId bigint,@UsuarioId bigint=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    DECLARE @Estado varchar(20),@BodegaId bigint,@Numero nvarchar(50);
    SELECT @Estado=Estado,@BodegaId=BodegaId,@Numero=Numero FROM inv.ConteoFisico WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoFisicoId;
    IF @Estado IS NULL THROW 51991,'El conteo no existe o no pertenece a la empresa.',1;
    IF @Estado='EN_CONTEO' BEGIN COMMIT; SELECT @ConteoFisicoId ConteoFisicoId,@Estado Estado,CAST(1 AS bit) YaExistia; RETURN; END;
    IF @Estado<>'PREPARACION' THROW 51992,'Solo un conteo en preparación puede iniciarse.',1;
    IF NOT EXISTS(SELECT 1 FROM inv.ConteoFisicoLinea WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoFisicoId)
        INSERT inv.ConteoFisicoLinea(EmpresaId,ConteoFisicoId,ArticuloId,ExistenciaTeorica)
        SELECT @EmpresaId,@ConteoFisicoId,ArticuloId,Existencia FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId;
    ELSE
        UPDATE l SET ExistenciaTeorica=CASE WHEN l.LoteId IS NOT NULL THEN COALESCE(sl.Existencia,0) WHEN l.UbicacionId IS NOT NULL THEN COALESCE(su.Existencia,0) ELSE COALESCE(sb.Existencia,0) END
        FROM inv.ConteoFisicoLinea l
        LEFT JOIN inv.SaldoArticuloBodega sb ON sb.EmpresaId=l.EmpresaId AND sb.BodegaId=@BodegaId AND sb.ArticuloId=l.ArticuloId
        LEFT JOIN inv.SaldoArticuloUbicacion su ON su.EmpresaId=l.EmpresaId AND su.BodegaId=@BodegaId AND su.UbicacionId=l.UbicacionId AND su.ArticuloId=l.ArticuloId
        LEFT JOIN inv.SaldoArticuloLoteUbicacion sl ON sl.EmpresaId=l.EmpresaId AND sl.BodegaId=@BodegaId AND sl.UbicacionId=l.UbicacionId AND sl.ArticuloId=l.ArticuloId AND sl.LoteId=l.LoteId
        WHERE l.EmpresaId=@EmpresaId AND l.ConteoFisicoId=@ConteoFisicoId;
    INSERT inv.BloqueoConteoFisico(EmpresaId,ConteoFisicoId,BodegaId,ArticuloId,UbicacionId,LoteId)
    SELECT @EmpresaId,@ConteoFisicoId,@BodegaId,ArticuloId,UbicacionId,LoteId FROM inv.ConteoFisicoLinea WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoFisicoId;
    UPDATE inv.ConteoFisico SET Estado='EN_CONTEO' WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoFisicoId;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresPosteriores,AplicacionOrigen)
    VALUES(@EmpresaId,@UsuarioId,'CONTEO_FISICO_INICIADO','inv.ConteoFisico',CONVERT(nvarchar(100),@ConteoFisicoId),@Numero,CONCAT(N'{"lineas":',(SELECT COUNT(*) FROM inv.ConteoFisicoLinea WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoFisicoId),N'}'),'INVENTARIO');
    COMMIT; SELECT @ConteoFisicoId ConteoFisicoId,CAST('EN_CONTEO' AS varchar(20)) Estado,CAST(0 AS bit) YaExistia;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_EnviarConteoRevision @EmpresaId bigint,@ConteoFisicoId bigint,@UsuarioId bigint=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    DECLARE @Estado varchar(20),@Numero nvarchar(50);
    SELECT @Estado=Estado,@Numero=Numero FROM inv.ConteoFisico WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoFisicoId;
    IF @Estado NOT IN('EN_CONTEO','RECONTEO') THROW 51993,'El conteo no está disponible para revisión.',1;
    IF EXISTS(SELECT 1 FROM inv.ConteoFisicoLinea l WHERE l.EmpresaId=@EmpresaId AND l.ConteoFisicoId=@ConteoFisicoId AND NOT EXISTS(SELECT 1 FROM inv.ConteoCaptura c WHERE c.EmpresaId=l.EmpresaId AND c.ConteoFisicoLineaId=l.ConteoFisicoLineaId))
        THROW 51994,'Todas las líneas requieren al menos una captura.',1;
    UPDATE inv.ConteoFisico SET Estado='EN_REVISION' WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoFisicoId;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresPosteriores,AplicacionOrigen)
    VALUES(@EmpresaId,@UsuarioId,'CONTEO_EN_REVISION','inv.ConteoFisico',CONVERT(nvarchar(100),@ConteoFisicoId),@Numero,N'{"estado":"EN_REVISION"}','INVENTARIO');
    COMMIT; SELECT @ConteoFisicoId ConteoFisicoId,CAST('EN_REVISION' AS varchar(20)) Estado;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_AprobarConteoFisico @EmpresaId bigint,@ConteoFisicoId bigint,@AprobacionesJson nvarchar(max),@UsuarioId bigint
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF ISJSON(@AprobacionesJson)<>1 THROW 51995,'Las aprobaciones deben enviarse como JSON válido.',1;
    BEGIN TRANSACTION;
    DECLARE @Estado varchar(20),@Numero nvarchar(50);
    SELECT @Estado=Estado,@Numero=Numero FROM inv.ConteoFisico WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoFisicoId;
    IF @Estado<>'EN_REVISION' THROW 51996,'El conteo debe estar en revisión para aprobarse.',1;
    IF (SELECT COUNT(*) FROM OPENJSON(@AprobacionesJson))<>(SELECT COUNT(*) FROM inv.ConteoFisicoLinea WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoFisicoId)
        THROW 51997,'Debe aprobarse una cantidad para cada línea.',1;
    UPDATE l SET CantidadAprobada=j.CantidadAprobada,DiferenciaAprobada=j.CantidadAprobada-l.ExistenciaTeorica
    FROM inv.ConteoFisicoLinea l JOIN OPENJSON(@AprobacionesJson) WITH(ConteoFisicoLineaId bigint '$.conteoFisicoLineaId',CantidadAprobada decimal(20,6) '$.cantidadAprobada') j ON j.ConteoFisicoLineaId=l.ConteoFisicoLineaId
    WHERE l.EmpresaId=@EmpresaId AND l.ConteoFisicoId=@ConteoFisicoId AND j.CantidadAprobada>=0;
    IF @@ROWCOUNT<>(SELECT COUNT(*) FROM inv.ConteoFisicoLinea WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoFisicoId) THROW 51998,'Una aprobación es inválida o no corresponde al conteo.',1;
    UPDATE inv.ConteoFisico SET Estado='APROBADO',AprobadoPorUsuarioId=@UsuarioId WHERE EmpresaId=@EmpresaId AND ConteoFisicoId=@ConteoFisicoId;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresPosteriores,AplicacionOrigen)
    VALUES(@EmpresaId,@UsuarioId,'CONTEO_FISICO_APROBADO','inv.ConteoFisico',CONVERT(nvarchar(100),@ConteoFisicoId),@Numero,N'{"estado":"APROBADO"}','INVENTARIO');
    COMMIT; SELECT @ConteoFisicoId ConteoFisicoId,CAST('APROBADO' AS varchar(20)) Estado;
END;
GO
