SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='077_cash_receipt_reversals')
    THROW 52770,'La migración 077 debe existir antes de reparar las reversiones.',1;
IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE name='CK_ReciboCaja_Reversion' AND parent_object_id=OBJECT_ID('cxc.ReciboCaja'))
BEGIN
    ALTER TABLE cxc.ReciboCaja WITH CHECK ADD CONSTRAINT CK_ReciboCaja_Reversion CHECK
        ((ReversionEstado IS NULL AND ReversionGuid IS NULL AND ReversionSnapshot IS NULL)
          OR (ReversionEstado IN('PENDIENTE','ENVIANDO','CONTABILIZADO','RECHAZADO','INCIERTO')
              AND ReversionGuid IS NOT NULL AND ReversionSnapshot IS NOT NULL AND ISJSON(ReversionSnapshot)=1
              AND ReversionFecha IS NOT NULL AND ReversionMotivo IS NOT NULL AND ReversionPor IS NOT NULL));
END;
IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE name='CK_ReciboCaja_Reversion' AND parent_object_id=OBJECT_ID('cxc.ReciboCaja') AND is_disabled=0 AND is_not_trusted=0)
    THROW 52771,'La restricción de reversión no quedó activa y validada.',1;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='078_repair_cash_receipt_reversal_check')
    INSERT core.SchemaMigration(MigrationId,Descripcion)
        VALUES('078_repair_cash_receipt_reversal_check',N'Validar restricción de reversión de recibos de caja');
COMMIT;
GO
