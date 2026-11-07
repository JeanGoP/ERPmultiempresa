SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='083_cash_receipt_customer_withholding')
BEGIN
    ALTER TABLE cxc.ReciboCaja ADD
        RetencionClienteValor decimal(18,2) NOT NULL CONSTRAINT DF_ReciboCaja_RetencionClienteValor DEFAULT 0,
        CuentaRetencionCliente varchar(16) NULL;
    EXEC(N'ALTER TABLE cxc.ReciboCaja ADD CONSTRAINT CK_ReciboCaja_RetencionCliente CHECK(
        RetencionClienteValor>=0 AND (Tipo=''NORMAL'' OR RetencionClienteValor=0)
        AND ((RetencionClienteValor=0 AND CuentaRetencionCliente IS NULL)
             OR (RetencionClienteValor>0 AND CuentaRetencionCliente LIKE ''13%'')))');
    INSERT core.SchemaMigration(MigrationId,Descripcion)
        VALUES('083_cash_receipt_customer_withholding',N'Retención practicada por cliente en recibos de caja normales');
END;
COMMIT;
GO
