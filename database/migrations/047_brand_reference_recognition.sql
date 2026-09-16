SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
CREATE OR ALTER FUNCTION inv.fn_MarcaPorReferenciaDescripcion(@EmpresaId bigint,@Referencia nvarchar(100),@Descripcion nvarchar(300))
RETURNS TABLE
AS RETURN (
    -- A known but unconfirmed/inactive reference must not fall back to another brand.
    SELECT CASE WHEN c.CatalogoMarcaDescripcionId IS NOT NULL
        THEN CASE WHEN c.Habilitada=1 AND m.Activa=1 THEN m.Nombre END
        ELSE d.Marca END AS Marca
    FROM (VALUES(1)) v(n)
    LEFT JOIN inv.CatalogoMarcaDescripcion c ON c.EmpresaId=@EmpresaId
        AND c.Referencia=NULLIF(LTRIM(RTRIM(@Referencia)),N'')
    LEFT JOIN inv.Marca m ON m.EmpresaId=c.EmpresaId AND m.MarcaId=c.MarcaId
    OUTER APPLY inv.fn_MarcaPorDescripcion(@EmpresaId,@Descripcion) d
);
GO
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='047_brand_reference_recognition')
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('047_brand_reference_recognition',N'Reconocer marca por referencia exacta de empresa antes de comparar descripción');
COMMIT;
GO
