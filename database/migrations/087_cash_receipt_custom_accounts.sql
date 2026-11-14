SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='087_cash_receipt_custom_accounts')
BEGIN
    ALTER TABLE cxc.ReciboCajaConcepto ADD LineaId bigint IDENTITY(1,1) NOT NULL;
    ALTER TABLE cxc.ReciboCajaConcepto ADD CuentaZeus varchar(16) NULL;
    ALTER TABLE cxc.ReciboCajaConcepto DROP CONSTRAINT PK_ReciboCajaConcepto;
    ALTER TABLE cxc.ReciboCajaConcepto ADD CONSTRAINT PK_ReciboCajaConcepto PRIMARY KEY(EmpresaId,ReciboCajaId,LineaId);
    CREATE UNIQUE INDEX UX_ReciboCajaConcepto_Fijo ON cxc.ReciboCajaConcepto(EmpresaId,ReciboCajaId,Codigo) WHERE Codigo<>'LIBRE';
    ALTER TABLE cxc.ReciboCajaConcepto DROP CONSTRAINT CK_ReciboCajaConcepto_Codigo;
    ALTER TABLE cxc.ReciboCajaConcepto ADD CONSTRAINT CK_ReciboCajaConcepto_Codigo
        CHECK(Codigo IN('ANTICIPO','SOAT','MATRICULA','IMPUESTOS','TRASLADOS','CENTRALES','OTROS','LIBRE'));
    EXEC(N'ALTER TABLE cxc.ReciboCajaConcepto ADD CONSTRAINT CK_ReciboCajaConcepto_CuentaZeus
        CHECK((Codigo=''LIBRE'' AND CuentaZeus IS NOT NULL AND LEN(TRIM(CuentaZeus))>0)
           OR (Codigo<>''LIBRE'' AND CuentaZeus IS NULL))');
    INSERT core.SchemaMigration(MigrationId,Descripcion)
        VALUES('087_cash_receipt_custom_accounts',N'Varias cuentas Zeus libres en un mismo recibo de anticipo');
END;
COMMIT;
GO
