SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='076_company_receivable_collection_order')
BEGIN
    ALTER TABLE core.Empresa ADD OrdenCobroCartera varchar(24) NOT NULL
        CONSTRAINT DF_Empresa_OrdenCobroCartera DEFAULT 'POR_FACTURA';
    EXEC(N'ALTER TABLE core.Empresa ADD CONSTRAINT CK_Empresa_OrdenCobroCartera
        CHECK(OrdenCobroCartera IN(''POR_FACTURA'',''MAS_VENCIDA''))');
    INSERT core.SchemaMigration(MigrationId,Descripcion)
        VALUES('076_company_receivable_collection_order',N'Orden de recaudo de cuotas configurable por empresa');
END;
COMMIT;
GO
