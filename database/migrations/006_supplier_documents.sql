SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT 1 FROM core.SchemaMigration WHERE MigrationId = '006_supplier_documents')
BEGIN
    ALTER TABLE comp.DocumentoProveedor DROP CONSTRAINT CK_DocumentoProveedor_Xml;
    CREATE UNIQUE INDEX UX_RecepcionMercancia_Documento ON inv.RecepcionMercancia(EmpresaId, DocumentoProveedorId) WHERE DocumentoProveedorId IS NOT NULL;
    CREATE UNIQUE INDEX UX_CausacionServicio_Documento ON comp.CausacionServicio(EmpresaId, DocumentoProveedorId);
    INSERT core.SchemaMigration(MigrationId, Descripcion)
    VALUES ('006_supplier_documents', N'Persistencia idempotente de documentos y separación de recepción y causación');
END;
GO

CREATE OR ALTER PROCEDURE comp.usp_CrearDocumentoProveedor
    @EmpresaId                 bigint,
    @ProveedorIdentificacion   nvarchar(30),
    @ProveedorRazonSocial      nvarchar(200),
    @TipoDocumento             varchar(20),
    @NumeroDocumento           nvarchar(50),
    @FechaDocumento            date,
    @FechaVencimiento          date = NULL,
    @Moneda                    char(3) = 'COP',
    @CufeCude                  nvarchar(120) = NULL,
    @HashXml                   char(64) = NULL,
    @Fuente                    varchar(15),
    @SubtotalBruto             decimal(20,4),
    @DescuentoTotal            decimal(20,4),
    @ImpuestoTotal             decimal(20,4),
    @CargoTotal                decimal(20,4),
    @TotalPagar                decimal(20,4),
    @XmlOriginal               nvarchar(max) = NULL,
    @UsuarioId                 bigint = NULL,
    @LineasJson                nvarchar(max),
    @DocumentoGuid             uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NULLIF(LTRIM(RTRIM(@ProveedorIdentificacion)), N'') IS NULL THROW 51300, 'La identificación del proveedor es obligatoria.', 1;
    IF NULLIF(LTRIM(RTRIM(@ProveedorRazonSocial)), N'') IS NULL THROW 51301, 'La razón social del proveedor es obligatoria.', 1;
    IF NULLIF(LTRIM(RTRIM(@NumeroDocumento)), N'') IS NULL THROW 51302, 'El número del documento es obligatorio.', 1;
    IF ISJSON(@LineasJson) <> 1 THROW 51303, 'Las líneas deben enviarse como JSON válido.', 1;
    IF NOT EXISTS (SELECT 1 FROM OPENJSON(@LineasJson)) THROW 51304, 'El documento debe tener al menos una línea.', 1;
    IF @SubtotalBruto < 0 OR @DescuentoTotal < 0 OR @ImpuestoTotal < 0 OR @CargoTotal < 0 OR @TotalPagar < 0
        THROW 51305, 'Los valores del documento no pueden ser negativos.', 1;

    DECLARE @DocumentoExistenteId bigint;
    SELECT TOP (1) @DocumentoExistenteId = DocumentoProveedorId
    FROM comp.DocumentoProveedor
    WHERE EmpresaId=@EmpresaId
      AND ((@CufeCude IS NOT NULL AND CufeCude=@CufeCude) OR (@HashXml IS NOT NULL AND HashXml=@HashXml));
    IF @DocumentoExistenteId IS NOT NULL
    BEGIN
        SELECT @DocumentoExistenteId AS DocumentoProveedorId, CAST(1 AS bit) AS YaExistia;
        RETURN;
    END;

    BEGIN TRANSACTION;
    DECLARE @LockResult int;
    DECLARE @LockResource nvarchar(255) = CONCAT(N'DOC-PROV:', @EmpresaId, N':', @ProveedorIdentificacion, N':', @TipoDocumento, N':', @NumeroDocumento);
    EXEC @LockResult = sys.sp_getapplock @Resource=@LockResource, @LockMode='Exclusive', @LockOwner='Transaction', @LockTimeout=15000;
    IF @LockResult < 0 THROW 51306, 'No fue posible bloquear el documento del proveedor.', 1;

    DECLARE @TerceroId bigint;
    SELECT @TerceroId=TerceroId FROM ter.Tercero WITH (UPDLOCK,HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND TipoIdentificacion='NIT' AND NumeroIdentificacion=@ProveedorIdentificacion;
    IF @TerceroId IS NULL
    BEGIN
        INSERT ter.Tercero(EmpresaId,TipoIdentificacion,NumeroIdentificacion,RazonSocial,EsProveedor)
        VALUES (@EmpresaId,'NIT',@ProveedorIdentificacion,@ProveedorRazonSocial,1);
        SET @TerceroId=SCOPE_IDENTITY();
    END
    ELSE
        UPDATE ter.Tercero SET EsProveedor=1 WHERE EmpresaId=@EmpresaId AND TerceroId=@TerceroId AND EsProveedor=0;

    SET @DocumentoGuid=COALESCE(@DocumentoGuid,NEWID());
    INSERT comp.DocumentoProveedor
    (
        EmpresaId,DocumentoGuid,TerceroId,TipoDocumento,NumeroDocumento,FechaDocumento,FechaVencimiento,
        Moneda,CufeCude,HashXml,Fuente,Estado,SubtotalBruto,DescuentoTotal,ImpuestoTotal,CargoTotal,TotalPagar,
        XmlOriginal,CreadoPorUsuarioId
    )
    VALUES
    (
        @EmpresaId,@DocumentoGuid,@TerceroId,@TipoDocumento,@NumeroDocumento,@FechaDocumento,@FechaVencimiento,
        @Moneda,@CufeCude,@HashXml,@Fuente,'BORRADOR',@SubtotalBruto,@DescuentoTotal,@ImpuestoTotal,@CargoTotal,@TotalPagar,
        @XmlOriginal,@UsuarioId
    );
    DECLARE @DocumentoId bigint=SCOPE_IDENTITY();

    INSERT comp.DocumentoProveedorLinea
    (
        EmpresaId,DocumentoProveedorId,NumeroLinea,ArticuloId,CodigoExterno,Descripcion,Clasificacion,
        Cantidad,UnidadMedidaId,FactorAUnidadBase,PrecioUnitario,SubtotalBruto,Descuento,Impuesto,Cargo,TotalNeto
    )
    SELECT
        @EmpresaId,@DocumentoId,j.NumeroLinea,j.ArticuloId,j.CodigoExterno,j.Descripcion,j.Clasificacion,
        j.Cantidad,j.UnidadMedidaId,COALESCE(j.FactorAUnidadBase,1),j.PrecioUnitario,j.SubtotalBruto,
        COALESCE(j.Descuento,0),COALESCE(j.Impuesto,0),COALESCE(j.Cargo,0),j.TotalNeto
    FROM OPENJSON(@LineasJson)
    WITH
    (
        NumeroLinea int '$.numeroLinea', ArticuloId bigint '$.articuloId', CodigoExterno nvarchar(80) '$.codigoExterno',
        Descripcion nvarchar(500) '$.descripcion', Clasificacion varchar(25) '$.clasificacion',
        Cantidad decimal(20,6) '$.cantidad', UnidadMedidaId bigint '$.unidadMedidaId',
        FactorAUnidadBase decimal(20,10) '$.factorAUnidadBase', PrecioUnitario decimal(20,8) '$.precioUnitario',
        SubtotalBruto decimal(20,4) '$.subtotalBruto', Descuento decimal(20,4) '$.descuento',
        Impuesto decimal(20,4) '$.impuesto', Cargo decimal(20,4) '$.cargo', TotalNeto decimal(20,4) '$.totalNeto'
    ) j;

    IF @@ROWCOUNT <> (SELECT COUNT(*) FROM OPENJSON(@LineasJson)) THROW 51307, 'No fue posible guardar todas las líneas.', 1;

    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresPosteriores,AplicacionOrigen,CorrelationId)
    VALUES(@EmpresaId,@UsuarioId,'DOCUMENTO_PROVEEDOR_CREADO','comp.DocumentoProveedor',CONVERT(nvarchar(100),@DocumentoId),@NumeroDocumento,
           CONCAT(N'{"fuente":"',@Fuente,N'","lineas":',(SELECT COUNT(*) FROM OPENJSON(@LineasJson)),N'}'),'COMPRAS',@DocumentoGuid);

    COMMIT TRANSACTION;
    SELECT @DocumentoId AS DocumentoProveedorId, CAST(0 AS bit) AS YaExistia;
END;
GO

CREATE OR ALTER PROCEDURE comp.usp_PrepararProcesosDocumento
    @EmpresaId                bigint,
    @DocumentoProveedorId    bigint,
    @BodegaId                 bigint = NULL,
    @PeriodoInventarioId     bigint = NULL,
    @FechaContable           date,
    @NumeroRecepcion         nvarchar(50) = NULL,
    @NumeroCausacion         nvarchar(50) = NULL,
    @UsuarioId               bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;

    DECLARE @TerceroId bigint;
    DECLARE @Estado varchar(15);
    SELECT @TerceroId=TerceroId,@Estado=Estado FROM comp.DocumentoProveedor WITH (UPDLOCK,HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId;
    IF @TerceroId IS NULL THROW 51320, 'El documento del proveedor no existe.', 1;
    IF @Estado NOT IN ('BORRADOR','VALIDADO') THROW 51321, 'El documento no puede prepararse en su estado actual.', 1;

    DECLARE @LineasInventario int=(SELECT COUNT(*) FROM comp.DocumentoProveedorLinea WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId AND Clasificacion='INVENTARIO');
    DECLARE @LineasServicio int=(SELECT COUNT(*) FROM comp.DocumentoProveedorLinea WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId AND Clasificacion='SERVICIO_GASTO');
    DECLARE @RecepcionId bigint=NULL;
    DECLARE @CausacionId bigint=NULL;

    IF @LineasInventario>0
    BEGIN
        IF @BodegaId IS NULL OR @PeriodoInventarioId IS NULL OR NULLIF(@NumeroRecepcion,N'') IS NULL
            THROW 51322, 'Las líneas de inventario requieren bodega, periodo y número de recepción.', 1;
        IF EXISTS (SELECT 1 FROM comp.DocumentoProveedorLinea WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId AND Clasificacion='INVENTARIO' AND (ArticuloId IS NULL OR UnidadMedidaId IS NULL))
            THROW 51323, 'Todas las líneas de inventario deben estar relacionadas con un artículo y una unidad.', 1;

        SELECT @RecepcionId=RecepcionMercanciaId FROM inv.RecepcionMercancia WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId;
        IF @RecepcionId IS NULL
        BEGIN
            INSERT inv.RecepcionMercancia(EmpresaId,Numero,DocumentoProveedorId,TerceroId,BodegaId,FechaRecepcion,FechaContable,PeriodoInventarioId,Estado,CreadoPorUsuarioId)
            VALUES(@EmpresaId,@NumeroRecepcion,@DocumentoProveedorId,@TerceroId,@BodegaId,SYSUTCDATETIME(),@FechaContable,@PeriodoInventarioId,'BORRADOR',@UsuarioId);
            SET @RecepcionId=SCOPE_IDENTITY();

            INSERT inv.RecepcionMercanciaLinea
            (
                EmpresaId,RecepcionMercanciaId,DocumentoProveedorLineaId,NumeroLinea,ArticuloId,UnidadMedidaId,
                CantidadDocumento,FactorAUnidadBase,CantidadBase,CostoUnitarioDocumento,DescuentoLinea,
                CostoAdicionalAsignado,CostoTotalCapitalizable
            )
            SELECT EmpresaId,@RecepcionId,DocumentoProveedorLineaId,NumeroLinea,ArticuloId,UnidadMedidaId,
                   Cantidad,FactorAUnidadBase,CAST(Cantidad*FactorAUnidadBase AS decimal(20,6)),PrecioUnitario,Descuento,0,TotalNeto
            FROM comp.DocumentoProveedorLinea
            WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId AND Clasificacion='INVENTARIO';
        END;
    END;

    IF @LineasServicio>0
    BEGIN
        IF NULLIF(@NumeroCausacion,N'') IS NULL THROW 51324, 'Las líneas de servicio requieren número de causación.', 1;
        SELECT @CausacionId=CausacionServicioId FROM comp.CausacionServicio WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId;
        IF @CausacionId IS NULL
        BEGIN
            INSERT comp.CausacionServicio(EmpresaId,Numero,DocumentoProveedorId,TerceroId,FechaContable,Estado,CreadoPorUsuarioId)
            VALUES(@EmpresaId,@NumeroCausacion,@DocumentoProveedorId,@TerceroId,@FechaContable,'BORRADOR',@UsuarioId);
            SET @CausacionId=SCOPE_IDENTITY();
            INSERT comp.CausacionServicioLinea(EmpresaId,CausacionServicioId,DocumentoProveedorLineaId,NumeroLinea,Descripcion,Base,Impuestos,Retenciones,Total)
            SELECT EmpresaId,@CausacionId,DocumentoProveedorLineaId,NumeroLinea,Descripcion,TotalNeto,Impuesto,0,TotalNeto+Impuesto
            FROM comp.DocumentoProveedorLinea
            WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId AND Clasificacion='SERVICIO_GASTO';
        END;
    END;

    UPDATE comp.DocumentoProveedor SET Estado='VALIDADO' WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId AND Estado='BORRADOR';
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresPosteriores,AplicacionOrigen)
    SELECT @EmpresaId,@UsuarioId,'DOCUMENTO_PROVEEDOR_PREPARADO','comp.DocumentoProveedor',CONVERT(nvarchar(100),DocumentoProveedorId),NumeroDocumento,
           CONCAT(N'{"recepcionId":',COALESCE(CONVERT(varchar(30),@RecepcionId),'null'),N',"causacionId":',COALESCE(CONVERT(varchar(30),@CausacionId),'null'),N'}'),'COMPRAS'
    FROM comp.DocumentoProveedor WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId;

    COMMIT TRANSACTION;
    SELECT @DocumentoProveedorId AS DocumentoProveedorId,@RecepcionId AS RecepcionMercanciaId,@CausacionId AS CausacionServicioId,@LineasInventario AS LineasInventario,@LineasServicio AS LineasServicio;
END;
GO
