SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
IF OBJECT_ID('inv.fn_NormalizarDescripcionMarca') IS NULL
EXEC(N'CREATE FUNCTION inv.fn_NormalizarDescripcionMarca(@Descripcion nvarchar(300))
RETURNS nvarchar(300) WITH SCHEMABINDING
AS
BEGIN
    DECLARE @Valor nvarchar(300)=UPPER(REPLACE(REPLACE(REPLACE(REPLACE(@Descripcion,NCHAR(160),N'' ''),NCHAR(9),N'' ''),NCHAR(10),N'' ''),NCHAR(13),N'' ''));
    WHILE CHARINDEX(N''  '',@Valor)>0 SET @Valor=REPLACE(@Valor,N''  '',N'' '');
    RETURN LTRIM(RTRIM(@Valor));
END;');
GO
IF OBJECT_ID('inv.CatalogoMarcaDescripcion','U') IS NULL
BEGIN
    CREATE TABLE inv.CatalogoMarcaDescripcion(
        CatalogoMarcaDescripcionId bigint IDENTITY PRIMARY KEY,
        EmpresaId bigint NOT NULL REFERENCES core.Empresa(EmpresaId),
        Referencia nvarchar(100) NOT NULL,
        Descripcion nvarchar(300) NOT NULL,
        DescripcionNormalizada AS (inv.fn_NormalizarDescripcionMarca(Descripcion) COLLATE Latin1_General_100_CI_AI) PERSISTED,
        Marca nvarchar(100) NOT NULL,
        Linea nvarchar(100) NULL,
        Categoria nvarchar(100) NULL,
        Habilitada bit NOT NULL,
        MotivoRevision nvarchar(300) NULL,
        ArchivoOrigen nvarchar(255) NOT NULL,
        ArchivoSha256 char(64) NOT NULL,
        FilaOrigen int NOT NULL,
        ActualizadoUtc datetime2(7) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_CatalogoMarca_Referencia UNIQUE(EmpresaId,Referencia),
        CONSTRAINT CK_CatalogoMarca_Contenido CHECK(LEN(Referencia)>0 AND LEN(Descripcion)>0 AND LEN(Marca)>0)
    );
    CREATE INDEX IX_CatalogoMarca_Descripcion ON inv.CatalogoMarcaDescripcion(EmpresaId,DescripcionNormalizada) INCLUDE(Marca,Habilitada);
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy
        ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.CatalogoMarcaDescripcion,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.CatalogoMarcaDescripcion AFTER INSERT,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.CatalogoMarcaDescripcion AFTER UPDATE;');
END;
GO
-- Never infer by substring, brand token or supplier SKU. Ambiguous/held descriptions stay unresolved.
CREATE OR ALTER FUNCTION inv.fn_MarcaPorDescripcion(@EmpresaId bigint,@Descripcion nvarchar(300))
RETURNS TABLE
AS RETURN (
    SELECT CASE WHEN COUNT(*)>0 AND MIN(CONVERT(int,Habilitada))=1
        AND COUNT(DISTINCT Marca COLLATE Latin1_General_100_CI_AI)=1 THEN MIN(Marca) END AS Marca
    FROM inv.CatalogoMarcaDescripcion
    WHERE EmpresaId=@EmpresaId AND DescripcionNormalizada=inv.fn_NormalizarDescripcionMarca(@Descripcion) COLLATE Latin1_General_100_CI_AI
);
GO
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='045_company_brand_catalog')
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('045_company_brand_catalog',N'Catálogo privado por empresa para reconocer marcas por descripción exacta normalizada');
COMMIT;
GO
