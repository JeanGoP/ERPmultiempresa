SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='020_specific_cost_returns')
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('020_specific_cost_returns',N'Devoluciones de compra al costo específico de la recepción original');
GO

-- Los procedimientos definitivos se mantienen en 004_kardex_engine.sql y 011_supplier_returns.sql.
-- Esta migración documenta el cambio de firma y garantiza su orden de despliegue.
