SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='015_serialized_receipts')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
    CREATE TABLE comp.DocumentoProveedorLineaUnidad
    (
        DocumentoProveedorLineaUnidadId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        DocumentoProveedorLineaId bigint NOT NULL,
        NumeroUnidad int NOT NULL,
        Serial nvarchar(120) NULL,
        Motor nvarchar(120) NULL,
        Chasis nvarchar(120) NULL,
        Vin nvarchar(120) NULL,
        Color nvarchar(80) NULL,
        Modelo nvarchar(80) NULL,
        InformacionOriginal nvarchar(1000) NULL,
        CONSTRAINT PK_DocumentoProveedorLineaUnidad PRIMARY KEY CLUSTERED(DocumentoProveedorLineaUnidadId),
        CONSTRAINT UQ_DocumentoProveedorLineaUnidad UNIQUE(EmpresaId,DocumentoProveedorLineaId,NumeroUnidad),
        CONSTRAINT FK_DocumentoProveedorLineaUnidad_Linea FOREIGN KEY(EmpresaId,DocumentoProveedorLineaId) REFERENCES comp.DocumentoProveedorLinea(EmpresaId,DocumentoProveedorLineaId),
        CONSTRAINT CK_DocumentoProveedorLineaUnidad_Identificador CHECK(Serial IS NOT NULL OR Motor IS NOT NULL OR Chasis IS NOT NULL OR Vin IS NOT NULL)
    );
    CREATE TABLE inv.RecepcionMercanciaUnidad
    (
        RecepcionMercanciaUnidadId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        RecepcionMercanciaLineaId bigint NOT NULL,
        DocumentoProveedorLineaUnidadId bigint NULL,
        NumeroUnidad int NOT NULL,
        Serial nvarchar(120) NULL,
        Motor nvarchar(120) NULL,
        Chasis nvarchar(120) NULL,
        Vin nvarchar(120) NULL,
        Color nvarchar(80) NULL,
        Modelo nvarchar(80) NULL,
        InformacionOriginal nvarchar(1000) NULL,
        UnidadSerializadaId bigint NULL,
        CONSTRAINT PK_RecepcionMercanciaUnidad PRIMARY KEY CLUSTERED(RecepcionMercanciaUnidadId),
        CONSTRAINT UQ_RecepcionMercanciaUnidad_EmpresaId UNIQUE(EmpresaId,RecepcionMercanciaUnidadId),
        CONSTRAINT UQ_RecepcionMercanciaUnidad UNIQUE(EmpresaId,RecepcionMercanciaLineaId,NumeroUnidad),
        CONSTRAINT FK_RecepcionMercanciaUnidad_Linea FOREIGN KEY(EmpresaId,RecepcionMercanciaLineaId) REFERENCES inv.RecepcionMercanciaLinea(EmpresaId,RecepcionMercanciaLineaId),
        CONSTRAINT FK_RecepcionMercanciaUnidad_DocumentoUnidad FOREIGN KEY(DocumentoProveedorLineaUnidadId) REFERENCES comp.DocumentoProveedorLineaUnidad(DocumentoProveedorLineaUnidadId),
        CONSTRAINT FK_RecepcionMercanciaUnidad_Unidad FOREIGN KEY(EmpresaId,UnidadSerializadaId) REFERENCES inv.UnidadSerializada(EmpresaId,UnidadSerializadaId)
    );
    ALTER TABLE inv.UnidadSerializada ADD BodegaActualId bigint NULL,UbicacionActualId bigint NULL;
    EXEC(N'ALTER TABLE inv.UnidadSerializada ADD CONSTRAINT FK_UnidadSerializada_BodegaActual FOREIGN KEY(EmpresaId,BodegaActualId) REFERENCES inv.Bodega(EmpresaId,BodegaId);');
    EXEC(N'ALTER TABLE inv.UnidadSerializada ADD CONSTRAINT FK_UnidadSerializada_UbicacionActual FOREIGN KEY(EmpresaId,UbicacionActualId) REFERENCES inv.Ubicacion(EmpresaId,UbicacionId);');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON comp.DocumentoProveedorLineaUnidad;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON comp.DocumentoProveedorLineaUnidad AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON comp.DocumentoProveedorLineaUnidad AFTER UPDATE;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.RecepcionMercanciaUnidad;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.RecepcionMercanciaUnidad AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.RecepcionMercanciaUnidad AFTER UPDATE;');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('015_serialized_receipts',N'Persistencia y alta de serial, motor, chasis y VIN desde documentos de proveedor');
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO

CREATE OR ALTER PROCEDURE comp.usp_GuardarUnidadesSerializadasDocumento
    @EmpresaId bigint,@DocumentoProveedorId bigint,@UnidadesJson nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF ISJSON(@UnidadesJson)<>1 THROW 51890,'Las unidades serializadas deben enviarse como JSON válido.',1;
    BEGIN TRANSACTION;
    DECLARE @Estado varchar(15);
    SELECT @Estado=Estado FROM comp.DocumentoProveedor WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId;
    IF @Estado IS NULL THROW 51891,'El documento no existe o no pertenece a la empresa.',1;
    IF EXISTS(SELECT 1 FROM comp.DocumentoProveedorLineaUnidad u JOIN comp.DocumentoProveedorLinea l ON l.EmpresaId=u.EmpresaId AND l.DocumentoProveedorLineaId=u.DocumentoProveedorLineaId WHERE l.EmpresaId=@EmpresaId AND l.DocumentoProveedorId=@DocumentoProveedorId)
    BEGIN COMMIT; SELECT CAST(1 AS bit) YaExistian; RETURN; END;
    IF @Estado NOT IN('BORRADOR','VALIDADO') THROW 51892,'El documento ya no admite unidades serializadas.',1;
    INSERT comp.DocumentoProveedorLineaUnidad(EmpresaId,DocumentoProveedorLineaId,NumeroUnidad,Serial,Motor,Chasis,Vin,Color,Modelo,InformacionOriginal)
    SELECT @EmpresaId,l.DocumentoProveedorLineaId,j.NumeroUnidad,NULLIF(LTRIM(RTRIM(j.Serial)),N''),NULLIF(LTRIM(RTRIM(j.Motor)),N''),NULLIF(LTRIM(RTRIM(j.Chasis)),N''),NULLIF(LTRIM(RTRIM(j.Vin)),N''),NULLIF(LTRIM(RTRIM(j.Color)),N''),NULLIF(LTRIM(RTRIM(j.Modelo)),N''),j.InformacionOriginal
    FROM OPENJSON(@UnidadesJson) WITH(NumeroLinea int '$.numeroLinea',NumeroUnidad int '$.numeroUnidad',Serial nvarchar(120) '$.serial',Motor nvarchar(120) '$.motor',Chasis nvarchar(120) '$.chasis',Vin nvarchar(120) '$.vin',Color nvarchar(80) '$.color',Modelo nvarchar(80) '$.modelo',InformacionOriginal nvarchar(1000) '$.informacionOriginal') j
    JOIN comp.DocumentoProveedorLinea l ON l.EmpresaId=@EmpresaId AND l.DocumentoProveedorId=@DocumentoProveedorId AND l.NumeroLinea=j.NumeroLinea;
    IF @@ROWCOUNT<>(SELECT COUNT(*) FROM OPENJSON(@UnidadesJson)) THROW 51893,'Una unidad serializada no corresponde a una línea del documento.',1;
    COMMIT; SELECT CAST(0 AS bit) YaExistian;
END;
GO

CREATE OR ALTER TRIGGER inv.TR_RecepcionLinea_CopiarUnidades ON inv.RecepcionMercanciaLinea AFTER INSERT AS
BEGIN
    SET NOCOUNT ON;
    INSERT inv.RecepcionMercanciaUnidad(EmpresaId,RecepcionMercanciaLineaId,DocumentoProveedorLineaUnidadId,NumeroUnidad,Serial,Motor,Chasis,Vin,Color,Modelo,InformacionOriginal)
    SELECT i.EmpresaId,i.RecepcionMercanciaLineaId,u.DocumentoProveedorLineaUnidadId,u.NumeroUnidad,u.Serial,u.Motor,u.Chasis,u.Vin,u.Color,u.Modelo,u.InformacionOriginal
    FROM inserted i JOIN comp.DocumentoProveedorLineaUnidad u ON u.EmpresaId=i.EmpresaId AND u.DocumentoProveedorLineaId=i.DocumentoProveedorLineaId
    WHERE NOT EXISTS(SELECT 1 FROM inv.RecepcionMercanciaUnidad r WHERE r.EmpresaId=i.EmpresaId AND r.RecepcionMercanciaLineaId=i.RecepcionMercanciaLineaId AND r.NumeroUnidad=u.NumeroUnidad);
END;
GO

CREATE OR ALTER TRIGGER inv.TR_Recepcion_CrearUnidadesSerializadas ON inv.RecepcionMercancia AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.EmpresaId=i.EmpresaId AND d.RecepcionMercanciaId=i.RecepcionMercanciaId WHERE i.Estado='CONTABILIZADA' AND d.Estado<>'CONTABILIZADA') RETURN;
    IF EXISTS
    (
        SELECT 1 FROM inserted h JOIN deleted d ON d.EmpresaId=h.EmpresaId AND d.RecepcionMercanciaId=h.RecepcionMercanciaId
        JOIN inv.RecepcionMercanciaLinea l ON l.EmpresaId=h.EmpresaId AND l.RecepcionMercanciaId=h.RecepcionMercanciaId
        JOIN inv.Articulo a ON a.EmpresaId=l.EmpresaId AND a.ArticuloId=l.ArticuloId
        OUTER APPLY(SELECT COUNT(*) Cantidad FROM inv.RecepcionMercanciaUnidad u WHERE u.EmpresaId=l.EmpresaId AND u.RecepcionMercanciaLineaId=l.RecepcionMercanciaLineaId) x
        WHERE h.Estado='CONTABILIZADA' AND d.Estado<>'CONTABILIZADA' AND a.ManejaSerial=1 AND (l.CantidadBase<>FLOOR(l.CantidadBase) OR x.Cantidad<>CONVERT(int,l.CantidadBase))
    ) THROW 51894,'La cantidad de seriales, motores o chasis no coincide con las unidades recibidas del artículo serializado.',1;
    IF EXISTS
    (
        SELECT 1 FROM inserted h JOIN deleted d ON d.EmpresaId=h.EmpresaId AND d.RecepcionMercanciaId=h.RecepcionMercanciaId
        JOIN inv.RecepcionMercanciaLinea l ON l.EmpresaId=h.EmpresaId AND l.RecepcionMercanciaId=h.RecepcionMercanciaId
        JOIN inv.Articulo a ON a.EmpresaId=l.EmpresaId AND a.ArticuloId=l.ArticuloId
        JOIN inv.RecepcionMercanciaUnidad u ON u.EmpresaId=l.EmpresaId AND u.RecepcionMercanciaLineaId=l.RecepcionMercanciaLineaId
        WHERE h.Estado='CONTABILIZADA' AND d.Estado<>'CONTABILIZADA' AND a.ManejaSerial=0
    ) THROW 51895,'La línea contiene seriales pero el artículo no está configurado para manejar serial.',1;

    DECLARE @EmpresaId bigint,@RecepcionUnidadId bigint,@ArticuloId bigint,@LoteId bigint,@BodegaId bigint,@UbicacionId bigint,@UnidadId bigint,
            @Serial nvarchar(120),@Motor nvarchar(120),@Chasis nvarchar(120),@Vin nvarchar(120);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT u.EmpresaId,u.RecepcionMercanciaUnidadId,l.ArticuloId,l.LoteId,h.BodegaId,l.UbicacionId,u.Serial,u.Motor,u.Chasis,u.Vin
        FROM inserted h JOIN deleted d ON d.EmpresaId=h.EmpresaId AND d.RecepcionMercanciaId=h.RecepcionMercanciaId
        JOIN inv.RecepcionMercanciaLinea l ON l.EmpresaId=h.EmpresaId AND l.RecepcionMercanciaId=h.RecepcionMercanciaId
        JOIN inv.Articulo a ON a.EmpresaId=l.EmpresaId AND a.ArticuloId=l.ArticuloId AND a.ManejaSerial=1
        JOIN inv.RecepcionMercanciaUnidad u ON u.EmpresaId=l.EmpresaId AND u.RecepcionMercanciaLineaId=l.RecepcionMercanciaLineaId
        WHERE h.Estado='CONTABILIZADA' AND d.Estado<>'CONTABILIZADA' AND u.UnidadSerializadaId IS NULL ORDER BY l.ArticuloId,u.RecepcionMercanciaUnidadId;
    OPEN c; FETCH NEXT FROM c INTO @EmpresaId,@RecepcionUnidadId,@ArticuloId,@LoteId,@BodegaId,@UbicacionId,@Serial,@Motor,@Chasis,@Vin;
    WHILE @@FETCH_STATUS=0
    BEGIN
        INSERT inv.UnidadSerializada(EmpresaId,ArticuloId,LoteId,BodegaActualId,UbicacionActualId) VALUES(@EmpresaId,@ArticuloId,@LoteId,@BodegaId,@UbicacionId);
        SET @UnidadId=SCOPE_IDENTITY();
        UPDATE inv.RecepcionMercanciaUnidad SET UnidadSerializadaId=@UnidadId WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaUnidadId=@RecepcionUnidadId;
        INSERT inv.UnidadIdentificador(EmpresaId,UnidadSerializadaId,Tipo,Valor)
        SELECT @EmpresaId,@UnidadId,Tipo,Valor FROM (VALUES('SERIAL',@Serial),('MOTOR',@Motor),('CHASIS',@Chasis),('VIN',@Vin)) v(Tipo,Valor) WHERE Valor IS NOT NULL;
        FETCH NEXT FROM c INTO @EmpresaId,@RecepcionUnidadId,@ArticuloId,@LoteId,@BodegaId,@UbicacionId,@Serial,@Motor,@Chasis,@Vin;
    END;
    CLOSE c; DEALLOCATE c;
END;
GO
