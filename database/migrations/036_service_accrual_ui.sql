SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='036_service_accrual_ui')
BEGIN
    BEGIN TRANSACTION;
    ALTER TABLE comp.DocumentoProveedorLinea
        ADD Retencion decimal(20,4) NOT NULL CONSTRAINT DF_DocProveedorLinea_Retencion DEFAULT 0;
    EXEC(N'ALTER TABLE comp.DocumentoProveedorLinea ADD CONSTRAINT CK_DocumentoProveedorLinea_Retencion CHECK(Retencion>=0 AND Retencion<=TotalNeto+Impuesto);');
    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('036_service_accrual_ui',N'Retenciones por linea y exposicion visual de la causacion de servicios');
    COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE comp.usp_GuardarRetencionesDocumento
    @EmpresaId bigint,
    @DocumentoProveedorId bigint,
    @RetencionesJson nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF ISJSON(@RetencionesJson)<>1 THROW 52120,'Las retenciones deben enviarse como JSON valido.',1;
    IF EXISTS
    (
        SELECT 1
        FROM OPENJSON(@RetencionesJson) WITH(NumeroLinea int '$.numeroLinea',Retencion decimal(20,4) '$.retencion') j
        LEFT JOIN comp.DocumentoProveedorLinea l ON l.EmpresaId=@EmpresaId AND l.DocumentoProveedorId=@DocumentoProveedorId AND l.NumeroLinea=j.NumeroLinea
        WHERE l.DocumentoProveedorLineaId IS NULL OR l.Clasificacion<>'SERVICIO_GASTO' OR j.Retencion<0 OR j.Retencion>l.TotalNeto+l.Impuesto
    ) THROW 52121,'Una retencion no corresponde a una linea de servicio o supera su valor pagable.',1;

    UPDATE l SET Retencion=j.Retencion
    FROM comp.DocumentoProveedorLinea l
    JOIN OPENJSON(@RetencionesJson) WITH(NumeroLinea int '$.numeroLinea',Retencion decimal(20,4) '$.retencion') j ON j.NumeroLinea=l.NumeroLinea
    WHERE l.EmpresaId=@EmpresaId AND l.DocumentoProveedorId=@DocumentoProveedorId;
END;
GO

CREATE OR ALTER PROCEDURE comp.usp_AplicarRetencionesCausacionDocumento
    @EmpresaId bigint,
    @DocumentoProveedorId bigint
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    UPDATE c SET Retenciones=d.Retencion,Total=c.Base+c.Impuestos-d.Retencion
    FROM comp.CausacionServicioLinea c
    JOIN comp.DocumentoProveedorLinea d ON d.EmpresaId=c.EmpresaId AND d.DocumentoProveedorLineaId=c.DocumentoProveedorLineaId
    WHERE c.EmpresaId=@EmpresaId AND d.DocumentoProveedorId=@DocumentoProveedorId;
END;
GO
