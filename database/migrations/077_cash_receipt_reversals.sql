SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='077_cash_receipt_reversals')
BEGIN
    ALTER TABLE cxc.ReciboCaja ADD
        ReversionGuid uniqueidentifier NULL,
        ReversionFecha date NULL,
        ReversionMotivo nvarchar(300) NULL,
        ReversionSnapshot nvarchar(max) NULL,
        ReversionEstado varchar(20) NULL,
        ReversionFuente varchar(2) NULL,
        ReversionDocumento varchar(10) NULL,
        ReversionError nvarchar(2000) NULL,
        ReversionIntentos int NOT NULL CONSTRAINT DF_ReciboCaja_ReversionIntentos DEFAULT 0,
        ReversionActualizadoEnUtc datetime2 NULL,
        ReversionPor bigint NULL;
    EXEC(N'ALTER TABLE cxc.ReciboCaja DROP CONSTRAINT CK_ReciboCaja_Zeus');
    EXEC(N'ALTER TABLE cxc.ReciboCaja ADD CONSTRAINT CK_ReciboCaja_Zeus CHECK(ZeusEstado IN(''PENDIENTE'',''ENVIANDO'',''CONTABILIZADO'',''RECHAZADO'',''INCIERTO'',''REVERTIDO''))');
    EXEC(N'ALTER TABLE cxc.ReciboCaja ADD CONSTRAINT CK_ReciboCaja_Reversion CHECK(
        (ReversionEstado IS NULL AND ReversionGuid IS NULL AND ReversionSnapshot IS NULL)
        OR (ReversionEstado IN(''PENDIENTE'',''ENVIANDO'',''CONTABILIZADO'',''RECHAZADO'',''INCIERTO'')
            AND ReversionGuid IS NOT NULL AND ReversionSnapshot IS NOT NULL AND ISJSON(ReversionSnapshot)=1
            AND ReversionFecha IS NOT NULL AND ReversionMotivo IS NOT NULL AND ReversionPor IS NOT NULL))');
    IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE name='CK_ReciboCaja_Reversion' AND parent_object_id=OBJECT_ID('cxc.ReciboCaja'))
        THROW 52770,'No se creó la restricción de reversión de recibos.',1;
    EXEC(N'CREATE UNIQUE INDEX UX_ReciboCaja_ReversionGuid ON cxc.ReciboCaja(EmpresaId,ReversionGuid) WHERE ReversionGuid IS NOT NULL');
    IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name='UX_ReciboCaja_ReversionGuid' AND object_id=OBJECT_ID('cxc.ReciboCaja'))
        THROW 52771,'No se creó el índice de reversión de recibos.',1;
    INSERT core.SchemaMigration(MigrationId,Descripcion)
        VALUES('077_cash_receipt_reversals',N'Reversión compensatoria y auditada de recibos de caja en Zeus');
END;
COMMIT;
GO
