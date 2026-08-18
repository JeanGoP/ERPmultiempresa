SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='035_manual_goods_trace')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;

    CREATE TABLE comp.DocumentoProveedorLineaTrazabilidad
    (
        DocumentoProveedorLineaTrazabilidadId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        DocumentoProveedorLineaId bigint NOT NULL,
        NumeroLote nvarchar(80) NULL,
        FechaVencimiento date NULL,
        CONSTRAINT PK_DocumentoProveedorLineaTrazabilidad PRIMARY KEY CLUSTERED(DocumentoProveedorLineaTrazabilidadId),
        CONSTRAINT UQ_DocumentoProveedorLineaTrazabilidad UNIQUE(EmpresaId,DocumentoProveedorLineaId),
        CONSTRAINT FK_DocumentoProveedorLineaTrazabilidad_Linea FOREIGN KEY(EmpresaId,DocumentoProveedorLineaId) REFERENCES comp.DocumentoProveedorLinea(EmpresaId,DocumentoProveedorLineaId),
        CONSTRAINT CK_DocumentoProveedorLineaTrazabilidad_Dato CHECK(NumeroLote IS NOT NULL OR FechaVencimiento IS NOT NULL),
        CONSTRAINT CK_DocumentoProveedorLineaTrazabilidad_Vencimiento CHECK(FechaVencimiento IS NULL OR NumeroLote IS NOT NULL)
    );

    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON comp.DocumentoProveedorLineaTrazabilidad;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON comp.DocumentoProveedorLineaTrazabilidad AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON comp.DocumentoProveedorLineaTrazabilidad AFTER UPDATE;');

    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('035_manual_goods_trace',N'Lote y vencimiento para entradas manuales mediante el flujo común de recepción');
    COMMIT TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO

CREATE OR ALTER PROCEDURE comp.usp_GuardarTrazabilidadDocumento
    @EmpresaId bigint,
    @DocumentoProveedorId bigint,
    @TrazabilidadJson nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF ISJSON(@TrazabilidadJson)<>1 THROW 52040,'La trazabilidad de las líneas no contiene JSON válido.',1;
    IF NOT EXISTS(SELECT 1 FROM comp.DocumentoProveedor WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId AND Estado='BORRADOR')
        THROW 52041,'La trazabilidad solo puede guardarse sobre un documento en borrador.',1;
    IF EXISTS(SELECT 1 FROM OPENJSON(@TrazabilidadJson) WITH(NumeroLote nvarchar(80) '$.numeroLote',FechaVencimiento date '$.fechaVencimiento') j WHERE j.FechaVencimiento IS NOT NULL AND NULLIF(LTRIM(RTRIM(j.NumeroLote)),N'') IS NULL)
        THROW 52042,'La fecha de vencimiento requiere número de lote.',1;

    INSERT comp.DocumentoProveedorLineaTrazabilidad(EmpresaId,DocumentoProveedorLineaId,NumeroLote,FechaVencimiento)
    SELECT @EmpresaId,l.DocumentoProveedorLineaId,NULLIF(LTRIM(RTRIM(j.NumeroLote)),N''),j.FechaVencimiento
    FROM OPENJSON(@TrazabilidadJson)
    WITH(NumeroLinea int '$.numeroLinea',NumeroLote nvarchar(80) '$.numeroLote',FechaVencimiento date '$.fechaVencimiento') j
    JOIN comp.DocumentoProveedorLinea l ON l.EmpresaId=@EmpresaId AND l.DocumentoProveedorId=@DocumentoProveedorId AND l.NumeroLinea=j.NumeroLinea
    WHERE NULLIF(LTRIM(RTRIM(j.NumeroLote)),N'') IS NOT NULL OR j.FechaVencimiento IS NOT NULL;

    IF @@ROWCOUNT<>(SELECT COUNT(*) FROM OPENJSON(@TrazabilidadJson)) THROW 52043,'No fue posible relacionar la trazabilidad con todas las líneas.',1;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_AplicarLotesRecepcionDocumento
    @EmpresaId bigint,
    @DocumentoProveedorId bigint
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS
    (
        SELECT 1 FROM comp.DocumentoProveedorLineaTrazabilidad t
        JOIN comp.DocumentoProveedorLinea l ON l.EmpresaId=t.EmpresaId AND l.DocumentoProveedorLineaId=t.DocumentoProveedorLineaId
        WHERE l.EmpresaId=@EmpresaId AND l.DocumentoProveedorId=@DocumentoProveedorId
    ) RETURN;

    IF EXISTS
    (
        SELECT 1 FROM comp.DocumentoProveedorLineaTrazabilidad t
        JOIN comp.DocumentoProveedorLinea l ON l.EmpresaId=t.EmpresaId AND l.DocumentoProveedorLineaId=t.DocumentoProveedorLineaId
        JOIN inv.Articulo a ON a.EmpresaId=l.EmpresaId AND a.ArticuloId=l.ArticuloId
        WHERE l.EmpresaId=@EmpresaId AND l.DocumentoProveedorId=@DocumentoProveedorId AND a.ManejaLote=0
    ) THROW 52044,'Se informó lote para un artículo que no maneja lotes.',1;

    IF EXISTS
    (
        SELECT l.ArticuloId,t.NumeroLote
        FROM comp.DocumentoProveedorLineaTrazabilidad t
        JOIN comp.DocumentoProveedorLinea l ON l.EmpresaId=t.EmpresaId AND l.DocumentoProveedorLineaId=t.DocumentoProveedorLineaId
        WHERE l.EmpresaId=@EmpresaId AND l.DocumentoProveedorId=@DocumentoProveedorId
        GROUP BY l.ArticuloId,t.NumeroLote HAVING COUNT(DISTINCT t.FechaVencimiento)>1
    ) THROW 52045,'El mismo lote tiene fechas de vencimiento diferentes.',1;

    IF EXISTS
    (
        SELECT 1 FROM comp.DocumentoProveedorLineaTrazabilidad t
        JOIN comp.DocumentoProveedorLinea l ON l.EmpresaId=t.EmpresaId AND l.DocumentoProveedorLineaId=t.DocumentoProveedorLineaId
        JOIN inv.Lote x ON x.EmpresaId=l.EmpresaId AND x.ArticuloId=l.ArticuloId AND x.NumeroLote=t.NumeroLote
        WHERE l.EmpresaId=@EmpresaId AND l.DocumentoProveedorId=@DocumentoProveedorId
          AND x.FechaVencimiento IS NOT NULL AND t.FechaVencimiento IS NOT NULL AND x.FechaVencimiento<>t.FechaVencimiento
    ) THROW 52046,'El lote ya existe con una fecha de vencimiento diferente.',1;

    INSERT inv.Lote(EmpresaId,ArticuloId,NumeroLote,FechaVencimiento)
    SELECT DISTINCT @EmpresaId,l.ArticuloId,t.NumeroLote,t.FechaVencimiento
    FROM comp.DocumentoProveedorLineaTrazabilidad t
    JOIN comp.DocumentoProveedorLinea l ON l.EmpresaId=t.EmpresaId AND l.DocumentoProveedorLineaId=t.DocumentoProveedorLineaId
    WHERE l.EmpresaId=@EmpresaId AND l.DocumentoProveedorId=@DocumentoProveedorId
      AND NOT EXISTS(SELECT 1 FROM inv.Lote x WITH(UPDLOCK,HOLDLOCK) WHERE x.EmpresaId=@EmpresaId AND x.ArticuloId=l.ArticuloId AND x.NumeroLote=t.NumeroLote);

    UPDATE x SET FechaVencimiento=COALESCE(x.FechaVencimiento,t.FechaVencimiento)
    FROM inv.Lote x
    JOIN comp.DocumentoProveedorLinea l ON l.EmpresaId=x.EmpresaId AND l.ArticuloId=x.ArticuloId
    JOIN comp.DocumentoProveedorLineaTrazabilidad t ON t.EmpresaId=l.EmpresaId AND t.DocumentoProveedorLineaId=l.DocumentoProveedorLineaId AND t.NumeroLote=x.NumeroLote
    WHERE l.EmpresaId=@EmpresaId AND l.DocumentoProveedorId=@DocumentoProveedorId;

    UPDATE r SET LoteId=x.LoteId
    FROM inv.RecepcionMercanciaLinea r
    JOIN comp.DocumentoProveedorLinea l ON l.EmpresaId=r.EmpresaId AND l.DocumentoProveedorLineaId=r.DocumentoProveedorLineaId
    JOIN comp.DocumentoProveedorLineaTrazabilidad t ON t.EmpresaId=l.EmpresaId AND t.DocumentoProveedorLineaId=l.DocumentoProveedorLineaId
    JOIN inv.Lote x ON x.EmpresaId=l.EmpresaId AND x.ArticuloId=l.ArticuloId AND x.NumeroLote=t.NumeroLote
    WHERE l.EmpresaId=@EmpresaId AND l.DocumentoProveedorId=@DocumentoProveedorId;
END;
GO
