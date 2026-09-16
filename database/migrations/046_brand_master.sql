SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
IF OBJECT_ID('inv.Marca','U') IS NULL
BEGIN
    CREATE TABLE inv.Marca(
        MarcaId bigint IDENTITY PRIMARY KEY,
        EmpresaId bigint NOT NULL REFERENCES core.Empresa(EmpresaId),
        Nombre nvarchar(100) COLLATE Latin1_General_100_CI_AI NOT NULL,
        Activa bit NOT NULL DEFAULT 1,
        CONSTRAINT UQ_Marca_Nombre UNIQUE(EmpresaId,Nombre),
        CONSTRAINT UQ_Marca_Empresa UNIQUE(EmpresaId,MarcaId),
        CONSTRAINT CK_Marca_Nombre CHECK(LEN(LTRIM(RTRIM(Nombre)))>0)
    );
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy
        ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.Marca,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.Marca AFTER INSERT,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.Marca AFTER UPDATE;');
END;
IF COL_LENGTH('inv.CatalogoMarcaDescripcion','MarcaId') IS NULL
BEGIN
    ALTER TABLE inv.CatalogoMarcaDescripcion ADD MarcaId bigint NULL;
    EXEC(N'ALTER TABLE inv.CatalogoMarcaDescripcion ADD CONSTRAINT FK_Catalogo_Marca FOREIGN KEY(EmpresaId,MarcaId) REFERENCES inv.Marca(EmpresaId,MarcaId);');
END;
GO
-- Run seed across tenants, restoring the caller context afterwards.
DECLARE @Previous sql_variant=SESSION_CONTEXT(N'BypassRls');
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
INSERT inv.Marca(EmpresaId,Nombre)
SELECT c.EmpresaId,MIN(c.Marca) FROM inv.CatalogoMarcaDescripcion c
WHERE c.Habilitada=1 AND NOT EXISTS(SELECT 1 FROM inv.Marca m WHERE m.EmpresaId=c.EmpresaId AND m.Nombre=c.Marca COLLATE Latin1_General_100_CI_AI)
GROUP BY c.EmpresaId,c.Marca COLLATE Latin1_General_100_CI_AI;
UPDATE c SET MarcaId=m.MarcaId FROM inv.CatalogoMarcaDescripcion c
JOIN inv.Marca m ON m.EmpresaId=c.EmpresaId AND m.Nombre=c.Marca COLLATE Latin1_General_100_CI_AI
WHERE c.Habilitada=1 AND c.MarcaId IS NULL;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=@Previous;
GO
CREATE OR ALTER FUNCTION inv.fn_MarcaPorDescripcion(@EmpresaId bigint,@Descripcion nvarchar(300))
RETURNS TABLE
AS RETURN (
    SELECT CASE WHEN COUNT(*)>0 AND MIN(CASE WHEN c.Habilitada=1 AND m.Activa=1 THEN 1 ELSE 0 END)=1
        AND COUNT(DISTINCT m.MarcaId)=1 THEN MIN(m.Nombre) END AS Marca
    FROM inv.CatalogoMarcaDescripcion c
    LEFT JOIN inv.Marca m ON m.EmpresaId=c.EmpresaId AND m.MarcaId=c.MarcaId
    WHERE c.EmpresaId=@EmpresaId AND c.DescripcionNormalizada=inv.fn_NormalizarDescripcionMarca(@Descripcion) COLLATE Latin1_General_100_CI_AI
);
GO
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='046_brand_master')
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('046_brand_master',N'Maestro de marcas por empresa para reconocimiento de XML');
COMMIT;
GO
