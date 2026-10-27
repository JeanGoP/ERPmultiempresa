SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='081_cash_receipt_motorcycle_retention_income')
BEGIN
    ALTER TABLE cxc.ReciboCaja ADD IngresoRetencionMoto decimal(18,2) NOT NULL
        CONSTRAINT DF_ReciboCaja_IngresoRetencionMoto DEFAULT 0;
    EXEC(N'ALTER TABLE cxc.ReciboCaja ADD CONSTRAINT CK_ReciboCaja_IngresoRetencionMoto CHECK(IngresoRetencionMoto>=0 AND IngresoRetencionMoto<=Total AND (Tipo=''CARTERA'' OR IngresoRetencionMoto=0))');
    INSERT core.SchemaMigration(MigrationId,Descripcion)
        VALUES('081_cash_receipt_motorcycle_retention_income',N'Ingreso por retención de moto separado del recaudo de cartera');
END;
COMMIT;
GO
