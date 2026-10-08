SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='066_sales_classification_and_observations')
BEGIN
    ALTER TABLE ven.FacturaVenta ADD ClaseCartera varchar(20) NOT NULL
        CONSTRAINT DF_FacturaVenta_ClaseCartera DEFAULT 'SIN_CLASIFICAR';
    ALTER TABLE ven.FacturaVenta ADD Observacion nvarchar(1000) NULL;
    ALTER TABLE ven.FacturaVentaCuota ADD TipoCuota varchar(12) NOT NULL
        CONSTRAINT DF_FacturaVentaCuota_Tipo DEFAULT 'ORDINARIA';
    EXEC(N'ALTER TABLE ven.FacturaVentaCuota ADD CONSTRAINT CK_FacturaVentaCuota_Tipo
        CHECK(TipoCuota IN(''ORDINARIA'',''EXTRA''))');
    EXEC(N'ALTER TABLE ven.FacturaVenta ADD CONSTRAINT CK_FacturaVenta_ClaseCartera
        CHECK(ClaseCartera IN(''MOTO'',''OTROS'',''MIXTA'',''SIN_CLASIFICAR''))');
    EXEC(N'CREATE INDEX IX_FacturaVenta_ClaseCartera ON ven.FacturaVenta(EmpresaId,ClaseCartera,ClienteId,SaldoPendiente)
        INCLUDE(Numero,Vencimiento)');
    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('066_sales_classification_and_observations',N'Clasificacion de cartera, observaciones y cuotas extraordinarias');
END;
COMMIT;
GO
