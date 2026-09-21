SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='049_zeus_integration')
BEGIN
    CREATE TABLE core.ZeusConfiguracion(
        EmpresaId bigint NOT NULL PRIMARY KEY REFERENCES core.Empresa(EmpresaId),
        Configuracion nvarchar(max) NOT NULL CHECK(ISJSON(Configuracion)=1),
        Version int NOT NULL DEFAULT 1,
        ActualizadoPor bigint NOT NULL REFERENCES seg.Usuario(UsuarioId),
        ActualizadoEnUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
    CREATE TABLE core.ZeusEnvio(
        ZeusEnvioId bigint IDENTITY PRIMARY KEY,
        EmpresaId bigint NOT NULL,
        RecepcionMercanciaId bigint NOT NULL,
        Clave uniqueidentifier NOT NULL DEFAULT NEWID(),
        Estado varchar(25) NOT NULL DEFAULT 'REQUIERE_REVISION',
        Snapshot nvarchar(max) NULL CHECK(Snapshot IS NULL OR ISJSON(Snapshot)=1),
        Intentos int NOT NULL DEFAULT 0,
        Fuente varchar(2) NULL,
        Documento varchar(10) NULL,
        Error nvarchar(2000) NULL,
        AprobadoPor bigint NULL REFERENCES seg.Usuario(UsuarioId),
        CreadoEnUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
        ActualizadoEnUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_ZeusEnvio_Recepcion UNIQUE(EmpresaId,RecepcionMercanciaId),
        CONSTRAINT UQ_ZeusEnvio_Clave UNIQUE(Clave),
        CONSTRAINT FK_ZeusEnvio_Recepcion FOREIGN KEY(EmpresaId,RecepcionMercanciaId) REFERENCES inv.RecepcionMercancia(EmpresaId,RecepcionMercanciaId),
        CONSTRAINT CK_ZeusEnvio_Estado CHECK(Estado IN('REQUIERE_REVISION','PENDIENTE','ENVIANDO','CONTABILIZADO','RECHAZADO','INCIERTO'))
    );
    CREATE INDEX IX_ZeusEnvio_Cola ON core.ZeusEnvio(Estado,ActualizadoEnUtc) INCLUDE(EmpresaId);
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy
        ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.ZeusConfiguracion,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.ZeusConfiguracion AFTER INSERT,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.ZeusConfiguracion AFTER UPDATE,
        ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.ZeusEnvio,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.ZeusEnvio AFTER INSERT,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.ZeusEnvio AFTER UPDATE;');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('049_zeus_integration',N'Configuracion por empresa y cola transaccional de entradas para Zeus');
END;
GO
CREATE OR ALTER TRIGGER inv.TR_RecepcionMercancia_Zeus ON inv.RecepcionMercancia AFTER INSERT,UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.RecepcionMercanciaId=i.RecepcionMercanciaId
              JOIN core.ZeusEnvio e ON e.EmpresaId=i.EmpresaId AND e.RecepcionMercanciaId=i.RecepcionMercanciaId
              WHERE d.Estado='CONTABILIZADA' AND i.Estado<>'CONTABILIZADA' AND e.Estado IN('PENDIENTE','ENVIANDO','INCIERTO','CONTABILIZADO'))
        THROW 51705,'La entrada tiene un envio Zeus pendiente o contabilizado. Requiere conciliacion y reversa coordinada.',1;
    INSERT core.ZeusEnvio(EmpresaId,RecepcionMercanciaId)
    SELECT i.EmpresaId,i.RecepcionMercanciaId
    FROM inserted i
    LEFT JOIN deleted d ON d.RecepcionMercanciaId=i.RecepcionMercanciaId
    JOIN core.ZeusConfiguracion c ON c.EmpresaId=i.EmpresaId
    WHERE i.Estado='CONTABILIZADA' AND ISNULL(d.Estado,'')<>'CONTABILIZADA'
      AND NOT EXISTS(SELECT 1 FROM core.ZeusEnvio e WITH(UPDLOCK,HOLDLOCK)
                     WHERE e.EmpresaId=i.EmpresaId AND e.RecepcionMercanciaId=i.RecepcionMercanciaId);
END;
GO
COMMIT;
