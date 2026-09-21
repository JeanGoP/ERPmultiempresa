SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='052_warehouse_zeus_accounts')
BEGIN
    CREATE TABLE core.ZeusBodegaCuenta(
        EmpresaId bigint NOT NULL,
        BodegaId bigint NOT NULL,
        Configuracion nvarchar(max) NOT NULL CHECK(ISJSON(Configuracion)=1),
        Servidor nvarchar(150) NOT NULL,
        BaseDatos nvarchar(128) NOT NULL,
        Version int NOT NULL DEFAULT 1,
        ActualizadoPor bigint NOT NULL REFERENCES seg.Usuario(UsuarioId),
        ActualizadoEnUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_ZeusBodegaCuenta PRIMARY KEY(EmpresaId,BodegaId),
        CONSTRAINT FK_ZeusBodegaCuenta_Bodega FOREIGN KEY(EmpresaId,BodegaId) REFERENCES inv.Bodega(EmpresaId,BodegaId)
    );
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy
        ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.ZeusBodegaCuenta,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.ZeusBodegaCuenta AFTER INSERT,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.ZeusBodegaCuenta AFTER UPDATE;');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('052_warehouse_zeus_accounts',N'Cuentas contables Zeus por empresa y bodega');
END;
COMMIT;
