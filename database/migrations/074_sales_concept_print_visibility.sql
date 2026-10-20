SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='074_sales_concept_print_visibility')
BEGIN
    ALTER TABLE ven.ConceptoVenta ADD
        MostrarEnCuerpo bit NOT NULL CONSTRAINT DF_ConceptoVenta_MostrarEnCuerpo DEFAULT 1,
        MostrarEnTotales bit NOT NULL CONSTRAINT DF_ConceptoVenta_MostrarEnTotales DEFAULT 0;
    ALTER TABLE ven.FacturaVentaConcepto ADD
        MostrarEnCuerpo bit NOT NULL CONSTRAINT DF_FacturaVentaConcepto_MostrarEnCuerpo DEFAULT 1,
        MostrarEnTotales bit NOT NULL CONSTRAINT DF_FacturaVentaConcepto_MostrarEnTotales DEFAULT 0;
    EXEC(N'UPDATE ven.ConceptoVenta SET MostrarEnCuerpo=CASE WHEN UbicacionFormato=''TOTALES'' THEN 0 ELSE 1 END,
        MostrarEnTotales=CASE WHEN UbicacionFormato=''TOTALES'' THEN 1 ELSE 0 END');
    EXEC(N'UPDATE ven.FacturaVentaConcepto SET MostrarEnCuerpo=CASE WHEN UbicacionFormato=''TOTALES'' THEN 0 ELSE 1 END,
        MostrarEnTotales=CASE WHEN UbicacionFormato=''TOTALES'' THEN 1 ELSE 0 END');
    INSERT core.SchemaMigration(MigrationId,Descripcion)
        VALUES('074_sales_concept_print_visibility',N'Visibilidad independiente de conceptos en cuerpo y totales de la factura');
END;
COMMIT;
GO
