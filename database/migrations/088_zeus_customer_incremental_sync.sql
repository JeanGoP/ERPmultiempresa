SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='088_zeus_customer_incremental_sync')
BEGIN
    CREATE TABLE ven.ClienteSyncZeusEstado(
        EmpresaId bigint NOT NULL PRIMARY KEY,
        CursorNuevos varchar(25) NOT NULL DEFAULT '',
        CursorRevision varchar(25) NOT NULL DEFAULT '',
        ActualizadoEnUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT FK_ClienteSyncZeusEstado_Empresa FOREIGN KEY(EmpresaId) REFERENCES core.Empresa(EmpresaId)
    );
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy
        ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.ClienteSyncZeusEstado,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.ClienteSyncZeusEstado AFTER INSERT,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.ClienteSyncZeusEstado AFTER UPDATE;');
    INSERT core.SchemaMigration(MigrationId,Descripcion)
        VALUES('088_zeus_customer_incremental_sync',N'Cursores por empresa para sincronización incremental de clientes Zeus');
END;
COMMIT;
GO
