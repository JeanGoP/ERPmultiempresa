SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
CREATE OR ALTER TRIGGER seg.TR_UsuarioEmpresaRol_EmpresaUnica ON seg.UsuarioEmpresaRol AFTER INSERT,UPDATE AS
BEGIN
    SET NOCOUNT ON;
    -- No reasigna ni elimina accesos históricos. Permite desactivarlos para resolver conflictos.
    DECLARE @Touched TABLE(UsuarioId bigint PRIMARY KEY);
    INSERT @Touched SELECT u.UsuarioId FROM seg.Usuario u WITH(UPDLOCK,HOLDLOCK)
        WHERE EXISTS(SELECT 1 FROM inserted i WHERE i.UsuarioId=u.UsuarioId AND i.Activo=1);
    IF EXISTS(
        SELECT u.UsuarioId FROM seg.Usuario u JOIN @Touched t ON t.UsuarioId=u.UsuarioId
        WHERE u.EsSuperAdministrador=0
          AND EXISTS(SELECT 1 FROM inserted i WHERE i.UsuarioId=u.UsuarioId AND i.Activo=1)
          AND (SELECT COUNT(DISTINCT ur.EmpresaId) FROM seg.UsuarioEmpresaRol ur WITH(READCOMMITTEDLOCK) WHERE ur.UsuarioId=u.UsuarioId AND ur.Activo=1)>1
    ) THROW 51730,'Un usuario normal solo puede tener acceso activo a una empresa. Revisa su asignacion.',1;
END;
GO
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='050_single_company_users')
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('050_single_company_users',N'Empresa unica para usuarios no superadministradores, sin reasignar accesos existentes');
COMMIT;
