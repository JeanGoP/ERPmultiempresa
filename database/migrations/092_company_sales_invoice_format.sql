SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='092_company_sales_invoice_format')
BEGIN
    EXEC(N'ALTER TABLE core.Empresa ADD FormatoFacturaJson nvarchar(max) NULL;');
    EXEC(N'ALTER TABLE core.Empresa ADD CONSTRAINT CK_Empresa_FormatoFacturaJson CHECK(
        FormatoFacturaJson IS NULL OR (ISJSON(FormatoFacturaJson)=1 AND LEFT(LTRIM(FormatoFacturaJson),1)=N''{''));');
    EXEC(N'UPDATE core.Empresa
        SET FormatoFacturaJson=N''{"direccion":"CALLE 15 No. 12-99 BARRIO TIERRA GRATA","telefono":"7721302","ciudad":"MONTELIBANO","leyenda":null}''
        WHERE Nit=N''900060537'' AND FormatoFacturaJson IS NULL;');
    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('092_company_sales_invoice_format',N'Datos opcionales del encabezado de impresión de factura por empresa');
END;
COMMIT;
GO
