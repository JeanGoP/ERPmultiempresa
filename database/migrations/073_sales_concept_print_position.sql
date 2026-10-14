SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='073_sales_concept_print_position')
BEGIN
    ALTER TABLE ven.ConceptoVenta ADD UbicacionFormato varchar(10) NOT NULL
        CONSTRAINT DF_ConceptoVenta_UbicacionFormato DEFAULT 'CUERPO';
    EXEC(N'ALTER TABLE ven.ConceptoVenta ADD CONSTRAINT CK_ConceptoVenta_UbicacionFormato
        CHECK(UbicacionFormato IN(''CUERPO'',''TOTALES''))');
    ALTER TABLE ven.FacturaVentaConcepto ADD UbicacionFormato varchar(10) NOT NULL
        CONSTRAINT DF_FacturaVentaConcepto_UbicacionFormato DEFAULT 'CUERPO';
    EXEC(N'ALTER TABLE ven.FacturaVentaConcepto ADD CONSTRAINT CK_FacturaVentaConcepto_UbicacionFormato
        CHECK(UbicacionFormato IN(''CUERPO'',''TOTALES''))');
    INSERT core.SchemaMigration(MigrationId,Descripcion)
        VALUES('073_sales_concept_print_position',N'Ubicación de cada concepto de venta en cuerpo o totales del comprobante');
END;
COMMIT;
GO
