SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS (SELECT 1 FROM core.SchemaMigration WHERE MigrationId='089_transfer_observation')
BEGIN
    ALTER TABLE inv.Traslado ADD Observacion nvarchar(500) NULL;
    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('089_transfer_observation',N'Observación opcional en el encabezado del traslado');
END;
COMMIT;
GO
