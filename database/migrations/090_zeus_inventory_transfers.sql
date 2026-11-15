SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS (SELECT 1 FROM core.SchemaMigration WHERE MigrationId='090_zeus_inventory_transfers')
BEGIN
    CREATE TABLE core.ZeusTrasladoEnvio(
        EmpresaId bigint NOT NULL,
        TrasladoId bigint NOT NULL,
        Clave uniqueidentifier NOT NULL DEFAULT NEWID(),
        Estado varchar(24) NOT NULL,
        Snapshot nvarchar(max) NULL,
        Intentos int NOT NULL DEFAULT 0,
        Fuente varchar(2) NULL,
        Documento varchar(20) NULL,
        Error nvarchar(2000) NULL,
        CreadoEnUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
        ActualizadoEnUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_ZeusTrasladoEnvio PRIMARY KEY(EmpresaId,TrasladoId),
        CONSTRAINT UQ_ZeusTrasladoEnvio_Clave UNIQUE(Clave),
        CONSTRAINT FK_ZeusTrasladoEnvio_Traslado FOREIGN KEY(EmpresaId,TrasladoId) REFERENCES inv.Traslado(EmpresaId,TrasladoId),
        CONSTRAINT CK_ZeusTrasladoEnvio_Estado CHECK(Estado IN('PENDIENTE','ENVIANDO','CONTABILIZADO','REQUIERE_REVISION','RECHAZADO','INCIERTO')),
        CONSTRAINT CK_ZeusTrasladoEnvio_Snapshot CHECK((Snapshot IS NULL AND Estado='REQUIERE_REVISION') OR (Snapshot IS NOT NULL AND ISJSON(Snapshot)=1))
    );
    CREATE INDEX IX_ZeusTrasladoEnvio_Cola ON core.ZeusTrasladoEnvio(Estado,ActualizadoEnUtc,EmpresaId,TrasladoId);
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy
        ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.ZeusTrasladoEnvio,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.ZeusTrasladoEnvio AFTER INSERT,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.ZeusTrasladoEnvio AFTER UPDATE;');
    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('090_zeus_inventory_transfers',N'Cola contable en Zeus de traslados recibidos');
END;
COMMIT;
GO
