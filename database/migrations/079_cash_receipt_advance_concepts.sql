SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='079_cash_receipt_advance_concepts')
BEGIN
    CREATE TABLE cxc.ReciboCajaConcepto(
        EmpresaId bigint NOT NULL,
        ReciboCajaId bigint NOT NULL,
        Codigo varchar(12) NOT NULL,
        Valor decimal(18,2) NOT NULL,
        CONSTRAINT PK_ReciboCajaConcepto PRIMARY KEY(EmpresaId,ReciboCajaId,Codigo),
        CONSTRAINT FK_ReciboCajaConcepto_Recibo FOREIGN KEY(EmpresaId,ReciboCajaId)
            REFERENCES cxc.ReciboCaja(EmpresaId,ReciboCajaId),
        CONSTRAINT CK_ReciboCajaConcepto_Codigo CHECK(Codigo IN('ANTICIPO','SOAT','MATRICULA','OTROS')),
        CONSTRAINT CK_ReciboCajaConcepto_Valor CHECK(Valor>0)
    );
    EXEC(N'INSERT cxc.ReciboCajaConcepto(EmpresaId,ReciboCajaId,Codigo,Valor)
        SELECT EmpresaId,ReciboCajaId,''ANTICIPO'',Total
        FROM cxc.ReciboCaja WHERE Tipo=''ANTICIPO''');
    EXEC(N'IF EXISTS(SELECT 1 FROM cxc.ReciboCaja r WHERE r.Tipo=''ANTICIPO''
        AND NOT EXISTS(SELECT 1 FROM cxc.ReciboCajaConcepto d WHERE d.EmpresaId=r.EmpresaId AND d.ReciboCajaId=r.ReciboCajaId))
        THROW 52790,''No se pudo conservar el detalle de los anticipos anteriores.'',1');
    INSERT core.SchemaMigration(MigrationId,Descripcion)
        VALUES('079_cash_receipt_advance_concepts',N'Conceptos separados de anticipos para compra, SOAT, matrícula y otros');
END;
COMMIT;
GO
