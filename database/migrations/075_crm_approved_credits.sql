SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS (SELECT 1 FROM core.SchemaMigration WHERE MigrationId = '075_crm_approved_credits')
BEGIN
    CREATE TABLE ven.CrmApprovedCredit
    (
        ReceiptId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_CrmApprovedCredit PRIMARY KEY,
        EmpresaId bigint NOT NULL CONSTRAINT FK_CrmApprovedCredit_Empresa REFERENCES core.Empresa(EmpresaId),
        EventId uniqueidentifier NOT NULL,
        CrmCompanyId uniqueidentifier NOT NULL,
        ApplicationId uniqueidentifier NOT NULL,
        ApplicationNumber nvarchar(40) NOT NULL,
        PayloadJson nvarchar(max) NOT NULL,
        PayloadHash char(64) NOT NULL,
        Status varchar(30) NOT NULL CONSTRAINT DF_CrmApprovedCredit_Status DEFAULT 'PENDIENTE_REVISION',
        ReceivedUtc datetime2(7) NOT NULL CONSTRAINT DF_CrmApprovedCredit_ReceivedUtc DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_CrmApprovedCredit_Event UNIQUE (EmpresaId, EventId),
        CONSTRAINT UQ_CrmApprovedCredit_Application UNIQUE (EmpresaId, ApplicationId),
        CONSTRAINT CK_CrmApprovedCredit_Status CHECK (Status IN ('PENDIENTE_REVISION')),
        CONSTRAINT CK_CrmApprovedCredit_PayloadJson CHECK (ISJSON(PayloadJson) = 1)
    );
    IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = N'EmpresaSecurityPolicy' AND schema_id = SCHEMA_ID(N'seg'))
    BEGIN
        EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.CrmApprovedCredit');
        EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.CrmApprovedCredit AFTER INSERT');
        EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.CrmApprovedCredit AFTER UPDATE');
    END;
    INSERT core.SchemaMigration(MigrationId, Descripcion)
        VALUES ('075_crm_approved_credits', N'Recepción idempotente de créditos aprobados del CRM como ventas pendientes');
END;
COMMIT;
GO
