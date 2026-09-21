SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='053_supplier_zeus_sync')
BEGIN
    CREATE TABLE core.ZeusProveedorEnvio(
        EmpresaId bigint NOT NULL,
        TerceroId bigint NOT NULL,
        Estado varchar(15) NOT NULL DEFAULT 'EN_COLA',
        Mensaje nvarchar(1500) NULL,
        Servidor nvarchar(150) NULL,
        BaseDatos nvarchar(128) NULL,
        Intentos int NOT NULL DEFAULT 0,
        Intento uniqueidentifier NOT NULL DEFAULT NEWID(),
        SolicitadoPor bigint NOT NULL REFERENCES seg.Usuario(UsuarioId),
        ActualizadoEnUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_ZeusProveedorEnvio PRIMARY KEY(EmpresaId,TerceroId),
        CONSTRAINT FK_ZeusProveedorEnvio_Tercero FOREIGN KEY(EmpresaId,TerceroId) REFERENCES ter.Tercero(EmpresaId,TerceroId),
        CONSTRAINT CK_ZeusProveedorEnvio_Estado CHECK(Estado IN('EN_COLA','ENVIANDO','PENDIENTE','INCIERTO','CREADO','EXISTENTE'))
    );
    CREATE INDEX IX_ZeusProveedorEnvio_Cola ON core.ZeusProveedorEnvio(Estado,ActualizadoEnUtc);
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy
        ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.ZeusProveedorEnvio,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.ZeusProveedorEnvio AFTER INSERT,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.ZeusProveedorEnvio AFTER UPDATE;');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('053_supplier_zeus_sync',N'Cola durable de proveedores XML a Zeus por empresa');
END;
COMMIT;
