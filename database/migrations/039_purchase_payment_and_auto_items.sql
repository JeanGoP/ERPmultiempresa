SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH(N'comp.DocumentoProveedor',N'CondicionPago') IS NULL
BEGIN
    ALTER TABLE comp.DocumentoProveedor ADD CondicionPago varchar(10) NOT NULL
        CONSTRAINT DF_DocumentoProveedor_CondicionPago DEFAULT 'CONTADO';
END;
GO

IF COL_LENGTH(N'comp.DocumentoProveedor',N'DiasCredito') IS NULL
BEGIN
    ALTER TABLE comp.DocumentoProveedor ADD DiasCredito int NOT NULL
        CONSTRAINT DF_DocumentoProveedor_DiasCredito DEFAULT 0;
END;
GO

UPDATE comp.DocumentoProveedor
SET CondicionPago=CASE WHEN FechaVencimiento>FechaDocumento THEN 'CREDITO' ELSE 'CONTADO' END,
    DiasCredito=CASE WHEN FechaVencimiento>FechaDocumento THEN DATEDIFF(day,FechaDocumento,FechaVencimiento) ELSE 0 END;
GO

IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE name='CK_DocumentoProveedor_CondicionPago')
BEGIN
    ALTER TABLE comp.DocumentoProveedor ADD CONSTRAINT CK_DocumentoProveedor_CondicionPago
        CHECK((CondicionPago='CONTADO' AND DiasCredito=0) OR (CondicionPago='CREDITO' AND DiasCredito BETWEEN 1 AND 3650));
END;
GO

CREATE OR ALTER PROCEDURE comp.usp_AsegurarArticulosDocumentoXml
    @EmpresaId bigint,
    @ProveedorIdentificacion nvarchar(30),
    @ProveedorRazonSocial nvarchar(200),
    @UsuarioId bigint,
    @CrearArticulosFaltantes bit,
    @LineasJson nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @UsuarioId IS NULL THROW 51308,'Se requiere el usuario para crear u homologar artículos.',1;
    IF ISJSON(@LineasJson)<>1 THROW 51309,'Las líneas para homologación no contienen JSON válido.',1;

    DECLARE @TerceroId bigint;
    SELECT @TerceroId=TerceroId
    FROM ter.Tercero WITH(UPDLOCK,HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND TipoIdentificacion='NIT' AND NumeroIdentificacion=@ProveedorIdentificacion;

    IF @TerceroId IS NULL
    BEGIN
        INSERT ter.Tercero(EmpresaId,TipoIdentificacion,NumeroIdentificacion,RazonSocial,EsProveedor)
        VALUES(@EmpresaId,'NIT',@ProveedorIdentificacion,@ProveedorRazonSocial,1);
        SET @TerceroId=SCOPE_IDENTITY();
    END
    ELSE
        UPDATE ter.Tercero SET EsProveedor=1,Activo=1
        WHERE EmpresaId=@EmpresaId AND TerceroId=@TerceroId;

    DECLARE @Lineas table
    (
        NumeroLinea int NOT NULL PRIMARY KEY,
        ArticuloId bigint NULL,
        UnidadMedidaId bigint NULL,
        CodigoExterno nvarchar(80) NULL,
        Descripcion nvarchar(500) NOT NULL,
        UnidadCodigo nvarchar(20) NULL,
        ManejaSerial bit NOT NULL,
        ArticuloCreado bit NOT NULL DEFAULT 0,
        CodigoInterno nvarchar(50) NULL
    );

    INSERT @Lineas(NumeroLinea,ArticuloId,UnidadMedidaId,CodigoExterno,Descripcion,UnidadCodigo,ManejaSerial)
    SELECT NumeroLinea,ArticuloId,UnidadMedidaId,NULLIF(LTRIM(RTRIM(CodigoExterno)),N''),Descripcion,
           NULLIF(UPPER(LTRIM(RTRIM(UnidadCodigo))),N''),COALESCE(ManejaSerial,0)
    FROM OPENJSON(@LineasJson)
    WITH
    (
        NumeroLinea int '$.numeroLinea', ArticuloId bigint '$.articuloId', UnidadMedidaId bigint '$.unidadMedidaId',
        CodigoExterno nvarchar(80) '$.codigoExterno', Descripcion nvarchar(500) '$.descripcion',
        UnidadCodigo nvarchar(20) '$.unidadCodigo', ManejaSerial bit '$.manejaSerial', Clasificacion varchar(25) '$.clasificacion'
    ) j
    WHERE Clasificacion='INVENTARIO';

    UPDATE l
    SET ArticuloId=h.ArticuloId,
        UnidadMedidaId=COALESCE(h.UnidadMedidaId,a.UnidadBaseId),
        CodigoInterno=a.Codigo
    FROM @Lineas l
    JOIN comp.HomologacionArticuloProveedor h WITH(UPDLOCK,HOLDLOCK)
      ON h.EmpresaId=@EmpresaId AND h.TerceroId=@TerceroId AND h.CodigoExterno=l.CodigoExterno AND h.Activa=1
    JOIN inv.Articulo a ON a.EmpresaId=@EmpresaId AND a.ArticuloId=h.ArticuloId AND a.Activo=1
    WHERE l.ArticuloId IS NULL;

    UPDATE l
    SET UnidadMedidaId=COALESCE(l.UnidadMedidaId,a.UnidadBaseId),CodigoInterno=a.Codigo
    FROM @Lineas l
    JOIN inv.Articulo a ON a.EmpresaId=@EmpresaId AND a.ArticuloId=l.ArticuloId AND a.Activo=1;

    IF EXISTS(SELECT 1 FROM @Lineas WHERE ArticuloId IS NULL) AND @CrearArticulosFaltantes=0
        THROW 51310,'Hay líneas de inventario sin artículo interno u homologación.',1;

    DECLARE @NumeroLinea int,@CodigoExterno nvarchar(80),@Descripcion nvarchar(500),@UnidadCodigo nvarchar(20),@ManejaSerial bit;
    DECLARE lineas CURSOR LOCAL FAST_FORWARD FOR
        SELECT NumeroLinea,CodigoExterno,Descripcion,UnidadCodigo,ManejaSerial
        FROM @Lineas WHERE ArticuloId IS NULL ORDER BY NumeroLinea;
    OPEN lineas;
    FETCH NEXT FROM lineas INTO @NumeroLinea,@CodigoExterno,@Descripcion,@UnidadCodigo,@ManejaSerial;
    WHILE @@FETCH_STATUS=0
    BEGIN
        IF @CodigoExterno IS NULL
            SET @CodigoExterno=CONCAT(N'DESC-',LEFT(CONVERT(varchar(64),HASHBYTES('SHA2_256',LOWER(LTRIM(RTRIM(@Descripcion)))),2),16));

        DECLARE @ArticuloId bigint=NULL,@UnidadMedidaId bigint=NULL,@CodigoInterno nvarchar(50)=NULL;
        SELECT @ArticuloId=h.ArticuloId,@UnidadMedidaId=COALESCE(h.UnidadMedidaId,a.UnidadBaseId),@CodigoInterno=a.Codigo
        FROM comp.HomologacionArticuloProveedor h WITH(UPDLOCK,HOLDLOCK)
        JOIN inv.Articulo a ON a.EmpresaId=h.EmpresaId AND a.ArticuloId=h.ArticuloId AND a.Activo=1
        WHERE h.EmpresaId=@EmpresaId AND h.TerceroId=@TerceroId AND h.CodigoExterno=@CodigoExterno AND h.Activa=1;

        IF @ArticuloId IS NULL
        BEGIN
            SET @UnidadCodigo=CASE WHEN @UnidadCodigo IS NULL OR @UnidadCodigo IN(N'94',N'EA',N'H87',N'NIU',N'PCE') THEN N'UND' ELSE LEFT(@UnidadCodigo,20) END;
            SELECT @UnidadMedidaId=UnidadMedidaId FROM inv.UnidadMedida WITH(UPDLOCK,HOLDLOCK)
            WHERE EmpresaId=@EmpresaId AND Codigo=@UnidadCodigo;
            IF @UnidadMedidaId IS NULL
            BEGIN
                INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo)
                VALUES(@EmpresaId,@UnidadCodigo,CASE @UnidadCodigo WHEN N'UND' THEN N'Unidad' WHEN N'KGM' THEN N'Kilogramo' ELSE @UnidadCodigo END,@UnidadCodigo);
                SET @UnidadMedidaId=SCOPE_IDENTITY();
            END;

            DECLARE @TipoConsecutivo varchar(40)=CASE WHEN @ManejaSerial=1 THEN 'ARTICULO_MOTO' ELSE 'ARTICULO' END;
            DECLARE @Prefijo nvarchar(10)=CASE WHEN @ManejaSerial=1 THEN N'MOT' ELSE N'ART' END;
            DECLARE @Numero bigint;
            SELECT @Numero=SiguienteNumero FROM core.Consecutivo WITH(UPDLOCK,HOLDLOCK)
            WHERE EmpresaId=@EmpresaId AND TipoDocumento=@TipoConsecutivo;
            IF @Numero IS NULL
            BEGIN
                SET @Numero=1;
                INSERT core.Consecutivo(EmpresaId,TipoDocumento,Prefijo,SiguienteNumero)
                VALUES(@EmpresaId,@TipoConsecutivo,@Prefijo,2);
            END
            ELSE
                UPDATE core.Consecutivo SET SiguienteNumero=@Numero+1,Prefijo=@Prefijo
                WHERE EmpresaId=@EmpresaId AND TipoDocumento=@TipoConsecutivo;

            SET @CodigoInterno=CONCAT(@Prefijo,N'-',RIGHT(CONCAT(N'00000000',@Numero),8));
            INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId,ManejaSerial)
            VALUES(@EmpresaId,@CodigoInterno,LEFT(@Descripcion,300),'INVENTARIO',1,@UnidadMedidaId,@ManejaSerial);
            SET @ArticuloId=SCOPE_IDENTITY();
            INSERT inv.ArticuloUnidad(EmpresaId,ArticuloId,UnidadMedidaId,FactorAUnidadBase,EsUnidadCompra,EsUnidadVenta)
            VALUES(@EmpresaId,@ArticuloId,@UnidadMedidaId,1,1,1);

            INSERT comp.HomologacionArticuloProveedor
                (EmpresaId,TerceroId,CodigoExterno,DescripcionExterna,ArticuloId,UnidadMedidaId,FactorAUnidadBase,CreadoPorUsuarioId)
            VALUES(@EmpresaId,@TerceroId,@CodigoExterno,LEFT(@Descripcion,300),@ArticuloId,@UnidadMedidaId,1,@UsuarioId);

            INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
            VALUES(@EmpresaId,@UsuarioId,'ARTICULO_CREADO_XML','inv.Articulo',CONVERT(nvarchar(100),@ArticuloId),
                   CONCAT(N'{"codigo":"',STRING_ESCAPE(@CodigoInterno,'json'),N'","codigoProveedor":"',STRING_ESCAPE(@CodigoExterno,'json'),N'"}'),'COMPRAS');

            UPDATE @Lineas SET ArticuloCreado=1 WHERE NumeroLinea=@NumeroLinea;
        END;

        UPDATE @Lineas SET ArticuloId=@ArticuloId,UnidadMedidaId=@UnidadMedidaId,CodigoExterno=@CodigoExterno,CodigoInterno=@CodigoInterno
        WHERE NumeroLinea=@NumeroLinea;
        FETCH NEXT FROM lineas INTO @NumeroLinea,@CodigoExterno,@Descripcion,@UnidadCodigo,@ManejaSerial;
    END;
    CLOSE lineas;
    DEALLOCATE lineas;

    SELECT NumeroLinea,ArticuloId,UnidadMedidaId,CodigoExterno,CodigoInterno,ArticuloCreado
    FROM @Lineas ORDER BY NumeroLinea;
END;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='039_purchase_payment_and_auto_items')
BEGIN
    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('039_purchase_payment_and_auto_items',N'Condición de pago y creación automática de artículos desde documentos XML');
END;
GO
