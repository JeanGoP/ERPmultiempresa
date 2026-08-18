SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='034_automatic_xml_intake')
BEGIN
    BEGIN TRANSACTION;

    CREATE INDEX IX_DocumentoProveedor_Flujo
        ON comp.DocumentoProveedor(EmpresaId,Estado,CreadoEnUtc DESC)
        INCLUDE(TerceroId,TipoDocumento,NumeroDocumento,FechaDocumento,TotalPagar,HashXml,CufeCude);

    CREATE INDEX IX_RecepcionMercancia_Flujo
        ON inv.RecepcionMercancia(EmpresaId,Estado,CreadoEnUtc DESC)
        INCLUDE(DocumentoProveedorId,Numero,BodegaId,FechaContable,PeriodoInventarioId);

    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('034_automatic_xml_intake',N'Consulta y seguimiento de la entrada automática desde XML DIAN');

    COMMIT TRANSACTION;
END;
GO
