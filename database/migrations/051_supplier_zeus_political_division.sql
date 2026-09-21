SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
IF COL_LENGTH('ter.Tercero','DivisionPoliticaZeus') IS NULL
    EXEC(N'ALTER TABLE ter.Tercero ADD DivisionPoliticaZeus AS
        (CONVERT(varchar(7), CASE
            WHEN UPPER(LTRIM(RTRIM(PaisCodigo))) IN (''CO'',''COL'',''57'')
              AND LEN(LTRIM(RTRIM(CiudadCodigo)))=5
              AND LTRIM(RTRIM(CiudadCodigo)) COLLATE Latin1_General_100_BIN2 NOT LIKE ''%[^0-9]%''
            THEN ''57'' + LTRIM(RTRIM(CiudadCodigo)) ELSE NULL END));');
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='051_supplier_zeus_political_division')
    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('051_supplier_zeus_political_division',N'Division politica Zeus calculada por pais y ciudad del proveedor');
COMMIT;
