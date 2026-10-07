SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='064_sales_cost_centers')
BEGIN
    ALTER TABLE ven.FacturaVenta ADD CentroCostoIngresoZeus varchar(16) NULL;
    ALTER TABLE ven.FacturaVentaConcepto ADD CentroCostoZeus varchar(16) NULL;
    INSERT core.SchemaMigration(MigrationId,Descripcion)
        VALUES('064_sales_cost_centers',N'Centro de costo Zeus por factura y por concepto de venta');
END;
COMMIT;
GO
