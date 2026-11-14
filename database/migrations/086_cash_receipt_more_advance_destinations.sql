SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='086_cash_receipt_more_advance_destinations')
BEGIN
    ALTER TABLE cxc.ReciboCajaConcepto DROP CONSTRAINT CK_ReciboCajaConcepto_Codigo;
    ALTER TABLE cxc.ReciboCajaConcepto ADD CONSTRAINT CK_ReciboCajaConcepto_Codigo
        CHECK(Codigo IN('ANTICIPO','SOAT','MATRICULA','IMPUESTOS','TRASLADOS','CENTRALES','OTROS'));
    INSERT core.SchemaMigration(MigrationId,Descripcion)
        VALUES('086_cash_receipt_more_advance_destinations',N'Impuestos, traslados y consultas centrales de riesgo en anticipos recibidos');
END;
COMMIT;
GO
