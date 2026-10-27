SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='082_cash_receipt_early_payment_discount')
BEGIN
    ALTER TABLE cxc.ReciboCaja ADD DescuentoProntoPago decimal(18,2) NOT NULL
        CONSTRAINT DF_ReciboCaja_DescuentoProntoPago DEFAULT 0;
    EXEC(N'ALTER TABLE cxc.ReciboCaja ADD CONSTRAINT CK_ReciboCaja_DescuentoProntoPago CHECK(DescuentoProntoPago>=0 AND (Tipo=''CARTERA'' OR DescuentoProntoPago=0))');
    INSERT core.SchemaMigration(MigrationId,Descripcion)
        VALUES('082_cash_receipt_early_payment_discount',N'Descuento opcional por pronto pago en recaudos de cartera');
END;
COMMIT;
GO
