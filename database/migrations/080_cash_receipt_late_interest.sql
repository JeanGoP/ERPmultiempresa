SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='080_cash_receipt_late_interest')
BEGIN
    ALTER TABLE core.Empresa ADD MoraMensualPct decimal(7,4) NOT NULL
        CONSTRAINT DF_Empresa_MoraMensualPct DEFAULT 0;
    EXEC(N'ALTER TABLE core.Empresa ADD CONSTRAINT CK_Empresa_MoraMensualPct CHECK(MoraMensualPct BETWEEN 0 AND 100)');
    ALTER TABLE cxc.ReciboCaja ADD MoraTasaPct decimal(7,4) NOT NULL
        CONSTRAINT DF_ReciboCaja_MoraTasaPct DEFAULT 0,
        MoraCalculada decimal(18,2) NOT NULL CONSTRAINT DF_ReciboCaja_MoraCalculada DEFAULT 0,
        MoraValor decimal(18,2) NOT NULL CONSTRAINT DF_ReciboCaja_MoraValor DEFAULT 0;
    EXEC(N'ALTER TABLE cxc.ReciboCaja ADD CONSTRAINT CK_ReciboCaja_Mora CHECK(MoraTasaPct BETWEEN 0 AND 100 AND MoraCalculada>=0 AND MoraValor>=0 AND MoraValor<=Total AND (Tipo=''CARTERA'' OR MoraValor=0))');
    IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE name='CK_ReciboCaja_Mora' AND parent_object_id=OBJECT_ID('cxc.ReciboCaja'))
        THROW 52800,'No se creó la restricción de mora en recibos.',1;
    INSERT core.SchemaMigration(MigrationId,Descripcion)
        VALUES('080_cash_receipt_late_interest',N'Porcentaje mensual de mora por empresa e interés editable por recibo');
END;
COMMIT;
GO
