SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='057_company_zeus_connection')
BEGIN
    CREATE TABLE core.ZeusConexion(
        EmpresaId bigint NOT NULL PRIMARY KEY REFERENCES core.Empresa(EmpresaId),
        Servidor nvarchar(150) NOT NULL,
        BaseDatos nvarchar(128) NOT NULL,
        UsuarioSql nvarchar(128) NOT NULL,
        PasswordProtegido nvarchar(max) NOT NULL,
        ConfiarCertificado bit NOT NULL DEFAULT 0,
        Version int NOT NULL DEFAULT 1,
        ActualizadoPor bigint NOT NULL REFERENCES seg.Usuario(UsuarioId),
        ActualizadoEnUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy
      ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.ZeusConexion,
      ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.ZeusConexion AFTER INSERT,
      ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.ZeusConexion AFTER UPDATE;');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('057_company_zeus_connection',N'Conexiones Zeus por empresa con contraseña protegida por el backend');
END;
COMMIT;
GO
