SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
BEGIN TRANSACTION;
GO

CREATE OR ALTER PROCEDURE comp.usp_GuardarRetencionesDocumento
    @EmpresaId bigint,
    @DocumentoProveedorId bigint,
    @RetencionesJson nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @RetencionesJson IS NULL OR ISJSON(@RetencionesJson)<>1 OR LEFT(LTRIM(@RetencionesJson),1)<>'['
        THROW 52120,'Las retenciones deben enviarse como un arreglo JSON valido.',1;

    DECLARE @Retenciones TABLE(NumeroLinea int,Retencion decimal(20,4));
    INSERT @Retenciones(NumeroLinea,Retencion)
    SELECT NumeroLinea,Retencion
    FROM OPENJSON(@RetencionesJson) WITH(NumeroLinea int '$.numeroLinea',Retencion decimal(20,4) '$.retencion');

    IF EXISTS(SELECT 1 FROM @Retenciones WHERE NumeroLinea IS NULL OR Retencion IS NULL)
       OR EXISTS(SELECT 1 FROM @Retenciones GROUP BY NumeroLinea HAVING COUNT(*)>1)
        THROW 52120,'Cada retencion requiere una linea unica y un valor valido.',1;

    IF EXISTS
    (
        SELECT 1 FROM @Retenciones j
        LEFT JOIN comp.DocumentoProveedorLinea l
          ON l.EmpresaId=@EmpresaId AND l.DocumentoProveedorId=@DocumentoProveedorId AND l.NumeroLinea=j.NumeroLinea
        WHERE l.DocumentoProveedorLineaId IS NULL
           OR l.Clasificacion NOT IN('INVENTARIO','SERVICIO_GASTO')
           OR j.Retencion<0 OR j.Retencion>l.TotalNeto+l.Impuesto
    ) THROW 52121,'La retencion debe corresponder a una linea de mercancia o servicio de esta factura, ser no negativa y no superar su valor pagable.',1;

    UPDATE l SET Retencion=j.Retencion
    FROM comp.DocumentoProveedorLinea l
    JOIN @Retenciones j ON j.NumeroLinea=l.NumeroLinea
    WHERE l.EmpresaId=@EmpresaId AND l.DocumentoProveedorId=@DocumentoProveedorId;
END;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='054_purchase_inventory_retentions')
    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('054_purchase_inventory_retentions',N'Permite retenciones en compras de mercancia y servicios con validacion de linea, empresa y limite pagable');
COMMIT;
GO
