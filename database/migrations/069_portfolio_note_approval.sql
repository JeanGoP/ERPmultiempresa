SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='069_portfolio_note_approval')
BEGIN
    ALTER TABLE ven.RefinanciacionCartera ADD AprobadoPor bigint NULL,
        AprobadoEnUtc datetime2 NULL;
    EXEC(N'ALTER TABLE ven.RefinanciacionCartera ADD CONSTRAINT FK_RefinanciacionCartera_AprobadoPor
        FOREIGN KEY(AprobadoPor) REFERENCES seg.Usuario(UsuarioId)');
    ALTER TABLE ven.RefinanciacionCartera DROP CONSTRAINT DF_RefinanciacionCartera_Zeus;
    ALTER TABLE ven.RefinanciacionCartera ADD CONSTRAINT DF_RefinanciacionCartera_Zeus DEFAULT 'POR_APROBAR' FOR ZeusEstado;
    ALTER TABLE ven.RefinanciacionCartera DROP CONSTRAINT CK_RefinanciacionCartera_Estado;
    ALTER TABLE ven.RefinanciacionCartera ADD CONSTRAINT CK_RefinanciacionCartera_Estado
        CHECK(ZeusEstado IN('POR_APROBAR','PENDIENTE','ENVIANDO','CONTABILIZADO','RECHAZADO','INCIERTO','CANCELADO'));
    UPDATE ven.RefinanciacionCartera SET ZeusEstado='POR_APROBAR' WHERE ZeusEstado='PENDIENTE' AND ZeusIntentos=0;
    INSERT core.SchemaMigration(MigrationId,Descripcion)
        VALUES('069_portfolio_note_approval',N'Aprobación por segundo usuario de notas de cartera antes del envío a Zeus');
END;
COMMIT;
GO
