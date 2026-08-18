SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF COL_LENGTH(N'seg.Usuario',N'EsSuperAdministrador') IS NULL
BEGIN
    ALTER TABLE seg.Usuario ADD EsSuperAdministrador bit NOT NULL
        CONSTRAINT DF_Usuario_SuperAdministrador DEFAULT 0;
END;
GO

EXEC(N'
CREATE OR ALTER FUNCTION seg.fn_TienePermiso(@EmpresaId bigint,@UsuarioId bigint,@CodigoPermiso varchar(100))
RETURNS bit
AS
BEGIN
    DECLARE @Resultado bit=0,@PermisoId bigint,@Excepcion bit;
    IF EXISTS(SELECT 1 FROM seg.Usuario WHERE UsuarioId=@UsuarioId AND Activo=1 AND EsSuperAdministrador=1) RETURN 1;
    SELECT @PermisoId=PermisoId FROM seg.Permiso WHERE Codigo=@CodigoPermiso AND Activo=1;
    IF @PermisoId IS NULL RETURN 0;
    IF NOT EXISTS(SELECT 1 FROM seg.Usuario WHERE UsuarioId=@UsuarioId AND Activo=1) RETURN 0;
    IF NOT EXISTS(SELECT 1 FROM seg.UsuarioEmpresaRol WHERE EmpresaId=@EmpresaId AND UsuarioId=@UsuarioId AND Activo=1) RETURN 0;
    SELECT @Excepcion=Permitido FROM seg.UsuarioEmpresaPermiso WHERE EmpresaId=@EmpresaId AND UsuarioId=@UsuarioId AND PermisoId=@PermisoId;
    IF @Excepcion IS NOT NULL RETURN @Excepcion;
    IF EXISTS
    (
        SELECT 1 FROM seg.UsuarioEmpresaRol ur
        JOIN seg.RolPermiso rp ON rp.RolId=ur.RolId AND rp.PermisoId=@PermisoId
        WHERE ur.EmpresaId=@EmpresaId AND ur.UsuarioId=@UsuarioId AND ur.Activo=1
    ) SET @Resultado=1;
    RETURN @Resultado;
END;');
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='038_global_super_administrator')
BEGIN
    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('038_global_super_administrator',N'Superadministrador global y aprovisionamiento inicial de empresas');
END;
GO
