SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='071_portfolio_note_without_approval')
BEGIN
    ALTER TABLE ven.RefinanciacionCartera DROP CONSTRAINT DF_RefinanciacionCartera_Zeus;
    ALTER TABLE ven.RefinanciacionCartera ADD CONSTRAINT DF_RefinanciacionCartera_Zeus DEFAULT 'PENDIENTE' FOR ZeusEstado;
    UPDATE ven.RefinanciacionCartera
    SET ZeusEstado='PENDIENTE',ZeusActualizadoEnUtc=SYSUTCDATETIME()
    WHERE ZeusEstado='POR_APROBAR' AND ZeusIntentos=0 AND ZeusDocumento IS NULL;
    INSERT core.SchemaMigration(MigrationId,Descripcion)
        VALUES('071_portfolio_note_without_approval',N'Las notas de cartera se envían a Zeus al guardarse, sin aprobación de otro usuario');
END;
COMMIT;
GO
