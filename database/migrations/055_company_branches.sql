SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='055_company_branches')
BEGIN
    CREATE TABLE core.Sucursal(
        SucursalId bigint IDENTITY PRIMARY KEY,
        EmpresaId bigint NOT NULL REFERENCES core.Empresa(EmpresaId),
        Codigo nvarchar(20) NOT NULL,
        Nombre nvarchar(80) NOT NULL,
        Activa bit NOT NULL DEFAULT 1,
        CONSTRAINT UQ_Sucursal_Codigo UNIQUE(EmpresaId,Codigo),
        CONSTRAINT UQ_Sucursal_Nombre UNIQUE(EmpresaId,Nombre),
        CONSTRAINT UQ_Sucursal_Empresa UNIQUE(EmpresaId,SucursalId),
        CONSTRAINT CK_Sucursal_Textos CHECK(LEN(LTRIM(RTRIM(Codigo)))>0 AND LEN(LTRIM(RTRIM(Nombre)))>0)
    );
    DECLARE @PreviousBypass sql_variant=SESSION_CONTEXT(N'BypassRls');
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
    ;WITH names AS(
        SELECT DISTINCT c.EmpresaId,LTRIM(RTRIM(r.Sucursal)) Nombre
        FROM core.ZeusConfiguracion c CROSS APPLY OPENJSON(c.Configuracion,'$.FuentesAutomaticas')
        WITH(Sucursal nvarchar(80) '$.Sucursal') r
        WHERE LEN(LTRIM(RTRIM(r.Sucursal)))>0
    )
    INSERT core.Sucursal(EmpresaId,Codigo,Nombre)
    SELECT EmpresaId,CONCAT('S',ROW_NUMBER() OVER(PARTITION BY EmpresaId ORDER BY Nombre)),Nombre FROM names;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=@PreviousBypass;
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy
        ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.Sucursal,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.Sucursal AFTER INSERT,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.Sucursal AFTER UPDATE;');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('055_company_branches',N'Catálogo de sucursales por empresa para fuentes automáticas Zeus');
END;
COMMIT;
GO
