SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='041_warehouse_receipt_issue_management')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;

    ALTER TABLE inv.RecepcionMercanciaRevisionUnidad ADD
        ResultadoGestion varchar(30) NULL,
        ObservacionGestion nvarchar(1000) NULL,
        GestionadaPorUsuarioId bigint NULL,
        GestionadaEnUtc datetime2(7) NULL;

    ALTER TABLE inv.RecepcionMercanciaRevisionUnidad ADD
        CONSTRAINT FK_RecepcionRevision_GestionUsuario FOREIGN KEY(GestionadaPorUsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_RecepcionRevision_ResultadoGestion CHECK(ResultadoGestion IS NULL OR ResultadoGestion IN('RECLAMO_PROVEEDOR','AJUSTE_INVENTARIO','DEVOLUCION','ACEPTADA_DOCUMENTADA','OTRA')),
        CONSTRAINT CK_RecepcionRevision_GestionCompleta CHECK
        (
            (GestionadaEnUtc IS NULL AND GestionadaPorUsuarioId IS NULL AND ResultadoGestion IS NULL AND ObservacionGestion IS NULL)
            OR
            (GestionadaEnUtc IS NOT NULL AND GestionadaPorUsuarioId IS NOT NULL AND ResultadoGestion IS NOT NULL AND EstadoFisico IN('RECIBIDA_NOVEDAD','NO_RECIBIDA'))
        );

    CREATE INDEX IX_RecepcionRevision_NovedadPendiente
        ON inv.RecepcionMercanciaRevisionUnidad(EmpresaId,EstadoFisico,GestionadaEnUtc,RevisadoEnUtc DESC)
        INCLUDE(RecepcionMercanciaUnidadId,Observacion);

    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('041_warehouse_receipt_issue_management',N'Bandeja administrativa y trazabilidad de novedades de recepción');
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO
