SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;

IF NOT EXISTS (SELECT 1 FROM core.SchemaMigration WHERE MigrationId = '002_inventory_purchasing')
BEGIN
    BEGIN TRANSACTION;

    CREATE TABLE inv.UnidadMedida
    (
        UnidadMedidaId bigint        IDENTITY(1,1) NOT NULL,
        EmpresaId      bigint        NOT NULL,
        Codigo         nvarchar(20)  NOT NULL,
        Nombre         nvarchar(80)  NOT NULL,
        Simbolo        nvarchar(15)  NOT NULL,
        Activa         bit           NOT NULL CONSTRAINT DF_UnidadMedida_Activa DEFAULT 1,
        CONSTRAINT PK_UnidadMedida PRIMARY KEY CLUSTERED (UnidadMedidaId),
        CONSTRAINT UQ_UnidadMedida_EmpresaId UNIQUE (EmpresaId, UnidadMedidaId),
        CONSTRAINT UQ_UnidadMedida_Codigo UNIQUE (EmpresaId, Codigo),
        CONSTRAINT FK_UnidadMedida_Empresa FOREIGN KEY (EmpresaId) REFERENCES core.Empresa(EmpresaId)
    );

    CREATE TABLE inv.Articulo
    (
        ArticuloId             bigint           IDENTITY(1,1) NOT NULL,
        EmpresaId              bigint           NOT NULL,
        ArticuloGuid           uniqueidentifier NOT NULL CONSTRAINT DF_Articulo_Guid DEFAULT NEWSEQUENTIALID(),
        Codigo                 nvarchar(50)     NOT NULL,
        Descripcion            nvarchar(300)    NOT NULL,
        Tipo                   varchar(20)      NOT NULL,
        ManejaInventario       bit              NOT NULL CONSTRAINT DF_Articulo_Inventario DEFAULT 1,
        UnidadBaseId           bigint           NOT NULL,
        ManejaLote             bit              NOT NULL CONSTRAINT DF_Articulo_Lote DEFAULT 0,
        ManejaSerial           bit              NOT NULL CONSTRAINT DF_Articulo_Serial DEFAULT 0,
        RequiereVencimiento    bit              NOT NULL CONSTRAINT DF_Articulo_Vencimiento DEFAULT 0,
        PesoBaseKg             decimal(20,8)    NULL,
        VolumenBaseM3          decimal(20,10)   NULL,
        Activo                 bit              NOT NULL CONSTRAINT DF_Articulo_Activo DEFAULT 1,
        CreadoEnUtc            datetime2(7)     NOT NULL CONSTRAINT DF_Articulo_Fecha DEFAULT SYSUTCDATETIME(),
        RowVersion             rowversion       NOT NULL,
        CONSTRAINT PK_Articulo PRIMARY KEY CLUSTERED (ArticuloId),
        CONSTRAINT UQ_Articulo_EmpresaId UNIQUE (EmpresaId, ArticuloId),
        CONSTRAINT UQ_Articulo_Guid UNIQUE (ArticuloGuid),
        CONSTRAINT UQ_Articulo_Codigo UNIQUE (EmpresaId, Codigo),
        CONSTRAINT FK_Articulo_Empresa FOREIGN KEY (EmpresaId) REFERENCES core.Empresa(EmpresaId),
        CONSTRAINT FK_Articulo_UnidadBase FOREIGN KEY (EmpresaId, UnidadBaseId) REFERENCES inv.UnidadMedida(EmpresaId, UnidadMedidaId),
        CONSTRAINT CK_Articulo_Tipo CHECK (Tipo IN ('INVENTARIO','SERVICIO','ACTIVO_FIJO','CONCEPTO')),
        CONSTRAINT CK_Articulo_Peso CHECK (PesoBaseKg IS NULL OR PesoBaseKg >= 0),
        CONSTRAINT CK_Articulo_Volumen CHECK (VolumenBaseM3 IS NULL OR VolumenBaseM3 >= 0),
        CONSTRAINT CK_Articulo_ServicioInventario CHECK (Tipo <> 'SERVICIO' OR ManejaInventario = 0)
    );

    CREATE TABLE inv.ArticuloUnidad
    (
        ArticuloUnidadId bigint          IDENTITY(1,1) NOT NULL,
        EmpresaId        bigint          NOT NULL,
        ArticuloId       bigint          NOT NULL,
        UnidadMedidaId   bigint          NOT NULL,
        FactorAUnidadBase decimal(20,10) NOT NULL,
        EsUnidadCompra   bit             NOT NULL CONSTRAINT DF_ArticuloUnidad_Compra DEFAULT 0,
        EsUnidadVenta    bit             NOT NULL CONSTRAINT DF_ArticuloUnidad_Venta DEFAULT 0,
        CONSTRAINT PK_ArticuloUnidad PRIMARY KEY CLUSTERED (ArticuloUnidadId),
        CONSTRAINT UQ_ArticuloUnidad UNIQUE (EmpresaId, ArticuloId, UnidadMedidaId),
        CONSTRAINT FK_ArticuloUnidad_Articulo FOREIGN KEY (EmpresaId, ArticuloId) REFERENCES inv.Articulo(EmpresaId, ArticuloId),
        CONSTRAINT FK_ArticuloUnidad_Unidad FOREIGN KEY (EmpresaId, UnidadMedidaId) REFERENCES inv.UnidadMedida(EmpresaId, UnidadMedidaId),
        CONSTRAINT CK_ArticuloUnidad_Factor CHECK (FactorAUnidadBase > 0)
    );

    CREATE TABLE inv.Bodega
    (
        BodegaId          bigint          IDENTITY(1,1) NOT NULL,
        EmpresaId         bigint          NOT NULL,
        Codigo            nvarchar(30)    NOT NULL,
        Nombre            nvarchar(120)   NOT NULL,
        UsaUbicaciones    bit             NOT NULL CONSTRAINT DF_Bodega_Ubicaciones DEFAULT 0,
        EsTransito        bit             NOT NULL CONSTRAINT DF_Bodega_Transito DEFAULT 0,
        Activa            bit             NOT NULL CONSTRAINT DF_Bodega_Activa DEFAULT 1,
        RowVersion        rowversion      NOT NULL,
        CONSTRAINT PK_Bodega PRIMARY KEY CLUSTERED (BodegaId),
        CONSTRAINT UQ_Bodega_EmpresaId UNIQUE (EmpresaId, BodegaId),
        CONSTRAINT UQ_Bodega_Codigo UNIQUE (EmpresaId, Codigo),
        CONSTRAINT FK_Bodega_Empresa FOREIGN KEY (EmpresaId) REFERENCES core.Empresa(EmpresaId)
    );

    CREATE TABLE inv.Ubicacion
    (
        UbicacionId       bigint          IDENTITY(1,1) NOT NULL,
        EmpresaId         bigint          NOT NULL,
        BodegaId          bigint          NOT NULL,
        UbicacionPadreId  bigint          NULL,
        Codigo            nvarchar(50)    NOT NULL,
        Nombre            nvarchar(120)   NOT NULL,
        Nivel             tinyint         NOT NULL CONSTRAINT DF_Ubicacion_Nivel DEFAULT 1,
        Activa            bit             NOT NULL CONSTRAINT DF_Ubicacion_Activa DEFAULT 1,
        CONSTRAINT PK_Ubicacion PRIMARY KEY CLUSTERED (UbicacionId),
        CONSTRAINT UQ_Ubicacion_EmpresaId UNIQUE (EmpresaId, UbicacionId),
        CONSTRAINT UQ_Ubicacion_BodegaCodigo UNIQUE (EmpresaId, BodegaId, Codigo),
        CONSTRAINT FK_Ubicacion_Bodega FOREIGN KEY (EmpresaId, BodegaId) REFERENCES inv.Bodega(EmpresaId, BodegaId),
        CONSTRAINT FK_Ubicacion_Padre FOREIGN KEY (EmpresaId, UbicacionPadreId) REFERENCES inv.Ubicacion(EmpresaId, UbicacionId),
        CONSTRAINT CK_Ubicacion_Nivel CHECK (Nivel BETWEEN 1 AND 10)
    );

    CREATE TABLE inv.Lote
    (
        LoteId             bigint         IDENTITY(1,1) NOT NULL,
        EmpresaId          bigint         NOT NULL,
        ArticuloId         bigint         NOT NULL,
        NumeroLote         nvarchar(80)   NOT NULL,
        FechaFabricacion   date           NULL,
        FechaVencimiento   date           NULL,
        CreadoEnUtc        datetime2(7)   NOT NULL CONSTRAINT DF_Lote_Fecha DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_Lote PRIMARY KEY CLUSTERED (LoteId),
        CONSTRAINT UQ_Lote_EmpresaId UNIQUE (EmpresaId, LoteId),
        CONSTRAINT UQ_Lote_ArticuloNumero UNIQUE (EmpresaId, ArticuloId, NumeroLote),
        CONSTRAINT FK_Lote_Articulo FOREIGN KEY (EmpresaId, ArticuloId) REFERENCES inv.Articulo(EmpresaId, ArticuloId),
        CONSTRAINT CK_Lote_Fechas CHECK (FechaVencimiento IS NULL OR FechaFabricacion IS NULL OR FechaVencimiento >= FechaFabricacion)
    );

    CREATE TABLE inv.UnidadSerializada
    (
        UnidadSerializadaId bigint           IDENTITY(1,1) NOT NULL,
        EmpresaId           bigint           NOT NULL,
        UnidadGuid          uniqueidentifier NOT NULL CONSTRAINT DF_UnidadSerializada_Guid DEFAULT NEWSEQUENTIALID(),
        ArticuloId          bigint           NOT NULL,
        LoteId              bigint           NULL,
        Estado              varchar(20)      NOT NULL CONSTRAINT DF_UnidadSerializada_Estado DEFAULT 'DISPONIBLE',
        FechaGarantiaHasta  date             NULL,
        CONSTRAINT PK_UnidadSerializada PRIMARY KEY CLUSTERED (UnidadSerializadaId),
        CONSTRAINT UQ_UnidadSerializada_EmpresaId UNIQUE (EmpresaId, UnidadSerializadaId),
        CONSTRAINT UQ_UnidadSerializada_Guid UNIQUE (UnidadGuid),
        CONSTRAINT FK_UnidadSerializada_Articulo FOREIGN KEY (EmpresaId, ArticuloId) REFERENCES inv.Articulo(EmpresaId, ArticuloId),
        CONSTRAINT FK_UnidadSerializada_Lote FOREIGN KEY (EmpresaId, LoteId) REFERENCES inv.Lote(EmpresaId, LoteId),
        CONSTRAINT CK_UnidadSerializada_Estado CHECK (Estado IN ('DISPONIBLE','RESERVADA','EN_TRANSITO','VENDIDA','DEVUELTA','BAJA'))
    );

    CREATE TABLE inv.UnidadIdentificador
    (
        UnidadIdentificadorId bigint        IDENTITY(1,1) NOT NULL,
        EmpresaId             bigint        NOT NULL,
        UnidadSerializadaId   bigint        NOT NULL,
        Tipo                  varchar(20)   NOT NULL,
        Valor                 nvarchar(120) NOT NULL,
        CONSTRAINT PK_UnidadIdentificador PRIMARY KEY CLUSTERED (UnidadIdentificadorId),
        CONSTRAINT UQ_UnidadIdentificador_TipoValor UNIQUE (EmpresaId, Tipo, Valor),
        CONSTRAINT UQ_UnidadIdentificador_UnidadTipo UNIQUE (EmpresaId, UnidadSerializadaId, Tipo),
        CONSTRAINT FK_UnidadIdentificador_Unidad FOREIGN KEY (EmpresaId, UnidadSerializadaId) REFERENCES inv.UnidadSerializada(EmpresaId, UnidadSerializadaId),
        CONSTRAINT CK_UnidadIdentificador_Tipo CHECK (Tipo IN ('SERIAL','MOTOR','CHASIS','VIN','PLACA','OTRO'))
    );

    CREATE TABLE comp.DocumentoProveedor
    (
        DocumentoProveedorId bigint           IDENTITY(1,1) NOT NULL,
        EmpresaId             bigint           NOT NULL,
        DocumentoGuid         uniqueidentifier NOT NULL CONSTRAINT DF_DocumentoProveedor_Guid DEFAULT NEWSEQUENTIALID(),
        TerceroId             bigint           NOT NULL,
        TipoDocumento         varchar(20)      NOT NULL,
        NumeroDocumento       nvarchar(50)     NOT NULL,
        FechaDocumento        date             NOT NULL,
        FechaVencimiento      date             NULL,
        Moneda                char(3)          NOT NULL CONSTRAINT DF_DocumentoProveedor_Moneda DEFAULT 'COP',
        CufeCude              nvarchar(120)    NULL,
        HashXml               char(64)         NULL,
        Fuente                varchar(15)      NOT NULL,
        Estado                varchar(15)      NOT NULL CONSTRAINT DF_DocumentoProveedor_Estado DEFAULT 'BORRADOR',
        SubtotalBruto         decimal(20,4)    NOT NULL CONSTRAINT DF_DocumentoProveedor_Bruto DEFAULT 0,
        DescuentoTotal        decimal(20,4)    NOT NULL CONSTRAINT DF_DocumentoProveedor_Descuento DEFAULT 0,
        ImpuestoTotal         decimal(20,4)    NOT NULL CONSTRAINT DF_DocumentoProveedor_Impuesto DEFAULT 0,
        CargoTotal            decimal(20,4)    NOT NULL CONSTRAINT DF_DocumentoProveedor_Cargo DEFAULT 0,
        TotalPagar            decimal(20,4)    NOT NULL CONSTRAINT DF_DocumentoProveedor_Total DEFAULT 0,
        XmlOriginal           nvarchar(max)    NULL,
        CreadoPorUsuarioId    bigint           NULL,
        CreadoEnUtc           datetime2(7)     NOT NULL CONSTRAINT DF_DocumentoProveedor_Fecha DEFAULT SYSUTCDATETIME(),
        RowVersion            rowversion       NOT NULL,
        CONSTRAINT PK_DocumentoProveedor PRIMARY KEY CLUSTERED (DocumentoProveedorId),
        CONSTRAINT UQ_DocumentoProveedor_EmpresaId UNIQUE (EmpresaId, DocumentoProveedorId),
        CONSTRAINT UQ_DocumentoProveedor_Guid UNIQUE (DocumentoGuid),
        CONSTRAINT UQ_DocumentoProveedor_Numero UNIQUE (EmpresaId, TerceroId, TipoDocumento, NumeroDocumento),
        CONSTRAINT FK_DocumentoProveedor_Empresa FOREIGN KEY (EmpresaId) REFERENCES core.Empresa(EmpresaId),
        CONSTRAINT FK_DocumentoProveedor_Tercero FOREIGN KEY (EmpresaId, TerceroId) REFERENCES ter.Tercero(EmpresaId, TerceroId),
        CONSTRAINT FK_DocumentoProveedor_Usuario FOREIGN KEY (CreadoPorUsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_DocumentoProveedor_Tipo CHECK (TipoDocumento IN ('FACTURA','NOTA_CREDITO','NOTA_DEBITO','DOCUMENTO_SOPORTE','REMISION')),
        CONSTRAINT CK_DocumentoProveedor_Fuente CHECK (Fuente IN ('XML_DIAN','MANUAL','API')),
        CONSTRAINT CK_DocumentoProveedor_Estado CHECK (Estado IN ('BORRADOR','VALIDADO','CONTABILIZADO','REVERTIDO','RECHAZADO')),
        CONSTRAINT CK_DocumentoProveedor_Xml CHECK (XmlOriginal IS NULL OR ISJSON(N'{"contenido":"ok"}') = 1)
    );

    CREATE UNIQUE INDEX UX_DocumentoProveedor_Cufe ON comp.DocumentoProveedor(EmpresaId, CufeCude) WHERE CufeCude IS NOT NULL;
    CREATE UNIQUE INDEX UX_DocumentoProveedor_HashXml ON comp.DocumentoProveedor(EmpresaId, HashXml) WHERE HashXml IS NOT NULL;

    CREATE TABLE comp.DocumentoProveedorLinea
    (
        DocumentoProveedorLineaId bigint        IDENTITY(1,1) NOT NULL,
        EmpresaId                  bigint        NOT NULL,
        DocumentoProveedorId      bigint        NOT NULL,
        NumeroLinea                int           NOT NULL,
        ArticuloId                 bigint        NULL,
        CodigoExterno              nvarchar(80)  NULL,
        Descripcion                nvarchar(500) NOT NULL,
        Clasificacion              varchar(25)   NOT NULL,
        Cantidad                   decimal(20,6) NOT NULL,
        UnidadMedidaId             bigint        NULL,
        FactorAUnidadBase          decimal(20,10) NOT NULL CONSTRAINT DF_DocProveedorLinea_Factor DEFAULT 1,
        PrecioUnitario             decimal(20,8) NOT NULL,
        SubtotalBruto              decimal(20,4) NOT NULL,
        Descuento                  decimal(20,4) NOT NULL CONSTRAINT DF_DocProveedorLinea_Descuento DEFAULT 0,
        Impuesto                   decimal(20,4) NOT NULL CONSTRAINT DF_DocProveedorLinea_Impuesto DEFAULT 0,
        Cargo                      decimal(20,4) NOT NULL CONSTRAINT DF_DocProveedorLinea_Cargo DEFAULT 0,
        TotalNeto                  decimal(20,4) NOT NULL,
        CONSTRAINT PK_DocumentoProveedorLinea PRIMARY KEY CLUSTERED (DocumentoProveedorLineaId),
        CONSTRAINT UQ_DocumentoProveedorLinea_EmpresaId UNIQUE (EmpresaId, DocumentoProveedorLineaId),
        CONSTRAINT UQ_DocumentoProveedorLinea_Numero UNIQUE (EmpresaId, DocumentoProveedorId, NumeroLinea),
        CONSTRAINT FK_DocumentoProveedorLinea_Documento FOREIGN KEY (EmpresaId, DocumentoProveedorId) REFERENCES comp.DocumentoProveedor(EmpresaId, DocumentoProveedorId),
        CONSTRAINT FK_DocumentoProveedorLinea_Articulo FOREIGN KEY (EmpresaId, ArticuloId) REFERENCES inv.Articulo(EmpresaId, ArticuloId),
        CONSTRAINT FK_DocumentoProveedorLinea_Unidad FOREIGN KEY (EmpresaId, UnidadMedidaId) REFERENCES inv.UnidadMedida(EmpresaId, UnidadMedidaId),
        CONSTRAINT CK_DocumentoProveedorLinea_Clasificacion CHECK (Clasificacion IN ('INVENTARIO','SERVICIO_GASTO','COSTO_ADQUISICION','ACTIVO_FIJO')),
        CONSTRAINT CK_DocumentoProveedorLinea_Cantidad CHECK (Cantidad > 0),
        CONSTRAINT CK_DocumentoProveedorLinea_Factor CHECK (FactorAUnidadBase > 0),
        CONSTRAINT CK_DocumentoProveedorLinea_Valores CHECK (PrecioUnitario >= 0 AND SubtotalBruto >= 0 AND Descuento >= 0 AND Impuesto >= 0 AND Cargo >= 0 AND TotalNeto >= 0)
    );

    CREATE TABLE inv.RecepcionMercancia
    (
        RecepcionMercanciaId bigint           IDENTITY(1,1) NOT NULL,
        EmpresaId            bigint           NOT NULL,
        RecepcionGuid        uniqueidentifier NOT NULL CONSTRAINT DF_Recepcion_Guid DEFAULT NEWSEQUENTIALID(),
        Numero               nvarchar(50)     NOT NULL,
        DocumentoProveedorId bigint           NULL,
        TerceroId            bigint           NOT NULL,
        BodegaId             bigint           NOT NULL,
        FechaRecepcion       datetime2(7)     NOT NULL,
        FechaContable        date             NOT NULL,
        PeriodoInventarioId  bigint           NOT NULL,
        Estado               varchar(15)      NOT NULL CONSTRAINT DF_Recepcion_Estado DEFAULT 'BORRADOR',
        CreadoPorUsuarioId   bigint           NULL,
        CreadoEnUtc          datetime2(7)     NOT NULL CONSTRAINT DF_Recepcion_Fecha DEFAULT SYSUTCDATETIME(),
        ContabilizadoEnUtc   datetime2(7)     NULL,
        RowVersion           rowversion       NOT NULL,
        CONSTRAINT PK_RecepcionMercancia PRIMARY KEY CLUSTERED (RecepcionMercanciaId),
        CONSTRAINT UQ_RecepcionMercancia_EmpresaId UNIQUE (EmpresaId, RecepcionMercanciaId),
        CONSTRAINT UQ_RecepcionMercancia_Guid UNIQUE (RecepcionGuid),
        CONSTRAINT UQ_RecepcionMercancia_Numero UNIQUE (EmpresaId, Numero),
        CONSTRAINT FK_RecepcionMercancia_Documento FOREIGN KEY (EmpresaId, DocumentoProveedorId) REFERENCES comp.DocumentoProveedor(EmpresaId, DocumentoProveedorId),
        CONSTRAINT FK_RecepcionMercancia_Tercero FOREIGN KEY (EmpresaId, TerceroId) REFERENCES ter.Tercero(EmpresaId, TerceroId),
        CONSTRAINT FK_RecepcionMercancia_Bodega FOREIGN KEY (EmpresaId, BodegaId) REFERENCES inv.Bodega(EmpresaId, BodegaId),
        CONSTRAINT FK_RecepcionMercancia_Periodo FOREIGN KEY (EmpresaId, PeriodoInventarioId) REFERENCES core.PeriodoInventario(EmpresaId, PeriodoInventarioId),
        CONSTRAINT FK_RecepcionMercancia_Usuario FOREIGN KEY (CreadoPorUsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_RecepcionMercancia_Estado CHECK (Estado IN ('BORRADOR','VALIDADA','CONTABILIZADA','REVERTIDA','CANCELADA'))
    );

    CREATE TABLE inv.RecepcionMercanciaLinea
    (
        RecepcionMercanciaLineaId bigint        IDENTITY(1,1) NOT NULL,
        EmpresaId                 bigint        NOT NULL,
        IdempotencyKey            uniqueidentifier NOT NULL CONSTRAINT DF_RecepcionLinea_Idempotency DEFAULT NEWID(),
        RecepcionMercanciaId     bigint        NOT NULL,
        DocumentoProveedorLineaId bigint       NULL,
        NumeroLinea               int           NOT NULL,
        ArticuloId                bigint        NOT NULL,
        UnidadMedidaId            bigint        NOT NULL,
        CantidadDocumento         decimal(20,6) NOT NULL,
        FactorAUnidadBase         decimal(20,10) NOT NULL,
        CantidadBase              decimal(20,6) NOT NULL,
        CostoUnitarioDocumento    decimal(20,8) NOT NULL,
        DescuentoLinea            decimal(20,4) NOT NULL CONSTRAINT DF_RecepcionLinea_Descuento DEFAULT 0,
        CostoAdicionalAsignado    decimal(20,4) NOT NULL CONSTRAINT DF_RecepcionLinea_Adicional DEFAULT 0,
        CostoTotalCapitalizable   decimal(20,4) NOT NULL,
        UbicacionId               bigint        NULL,
        LoteId                    bigint        NULL,
        CONSTRAINT PK_RecepcionMercanciaLinea PRIMARY KEY CLUSTERED (RecepcionMercanciaLineaId),
        CONSTRAINT UQ_RecepcionMercanciaLinea_EmpresaId UNIQUE (EmpresaId, RecepcionMercanciaLineaId),
        CONSTRAINT UQ_RecepcionMercanciaLinea_Idempotency UNIQUE (EmpresaId, IdempotencyKey),
        CONSTRAINT UQ_RecepcionMercanciaLinea_Numero UNIQUE (EmpresaId, RecepcionMercanciaId, NumeroLinea),
        CONSTRAINT FK_RecepcionMercanciaLinea_Recepcion FOREIGN KEY (EmpresaId, RecepcionMercanciaId) REFERENCES inv.RecepcionMercancia(EmpresaId, RecepcionMercanciaId),
        CONSTRAINT FK_RecepcionMercanciaLinea_DocumentoLinea FOREIGN KEY (EmpresaId, DocumentoProveedorLineaId) REFERENCES comp.DocumentoProveedorLinea(EmpresaId, DocumentoProveedorLineaId),
        CONSTRAINT FK_RecepcionMercanciaLinea_Articulo FOREIGN KEY (EmpresaId, ArticuloId) REFERENCES inv.Articulo(EmpresaId, ArticuloId),
        CONSTRAINT FK_RecepcionMercanciaLinea_Unidad FOREIGN KEY (EmpresaId, UnidadMedidaId) REFERENCES inv.UnidadMedida(EmpresaId, UnidadMedidaId),
        CONSTRAINT FK_RecepcionMercanciaLinea_Ubicacion FOREIGN KEY (EmpresaId, UbicacionId) REFERENCES inv.Ubicacion(EmpresaId, UbicacionId),
        CONSTRAINT FK_RecepcionMercanciaLinea_Lote FOREIGN KEY (EmpresaId, LoteId) REFERENCES inv.Lote(EmpresaId, LoteId),
        CONSTRAINT CK_RecepcionMercanciaLinea_Cantidades CHECK (CantidadDocumento > 0 AND FactorAUnidadBase > 0 AND CantidadBase > 0),
        CONSTRAINT CK_RecepcionMercanciaLinea_Costos CHECK (CostoUnitarioDocumento >= 0 AND DescuentoLinea >= 0 AND CostoAdicionalAsignado >= 0 AND CostoTotalCapitalizable >= 0)
    );

    CREATE TABLE comp.CausacionServicio
    (
        CausacionServicioId  bigint           IDENTITY(1,1) NOT NULL,
        EmpresaId            bigint           NOT NULL,
        CausacionGuid        uniqueidentifier NOT NULL CONSTRAINT DF_CausacionServicio_Guid DEFAULT NEWSEQUENTIALID(),
        Numero               nvarchar(50)     NOT NULL,
        DocumentoProveedorId bigint           NOT NULL,
        TerceroId            bigint           NOT NULL,
        FechaContable        date             NOT NULL,
        Estado               varchar(15)      NOT NULL CONSTRAINT DF_CausacionServicio_Estado DEFAULT 'BORRADOR',
        CentroCostoCodigo    nvarchar(50)     NULL,
        ProyectoCodigo       nvarchar(50)     NULL,
        CreadoPorUsuarioId   bigint           NULL,
        CreadoEnUtc          datetime2(7)     NOT NULL CONSTRAINT DF_CausacionServicio_Fecha DEFAULT SYSUTCDATETIME(),
        RowVersion           rowversion       NOT NULL,
        CONSTRAINT PK_CausacionServicio PRIMARY KEY CLUSTERED (CausacionServicioId),
        CONSTRAINT UQ_CausacionServicio_EmpresaId UNIQUE (EmpresaId, CausacionServicioId),
        CONSTRAINT UQ_CausacionServicio_Guid UNIQUE (CausacionGuid),
        CONSTRAINT UQ_CausacionServicio_Numero UNIQUE (EmpresaId, Numero),
        CONSTRAINT FK_CausacionServicio_Documento FOREIGN KEY (EmpresaId, DocumentoProveedorId) REFERENCES comp.DocumentoProveedor(EmpresaId, DocumentoProveedorId),
        CONSTRAINT FK_CausacionServicio_Tercero FOREIGN KEY (EmpresaId, TerceroId) REFERENCES ter.Tercero(EmpresaId, TerceroId),
        CONSTRAINT FK_CausacionServicio_Usuario FOREIGN KEY (CreadoPorUsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_CausacionServicio_Estado CHECK (Estado IN ('BORRADOR','VALIDADA','CONTABILIZADA','REVERTIDA','CANCELADA'))
    );

    CREATE TABLE comp.CausacionServicioLinea
    (
        CausacionServicioLineaId bigint        IDENTITY(1,1) NOT NULL,
        EmpresaId                bigint        NOT NULL,
        CausacionServicioId      bigint        NOT NULL,
        DocumentoProveedorLineaId bigint       NOT NULL,
        NumeroLinea              int           NOT NULL,
        Descripcion              nvarchar(500) NOT NULL,
        CuentaContableCodigo     nvarchar(30)  NULL,
        Base                     decimal(20,4) NOT NULL,
        Impuestos                decimal(20,4) NOT NULL CONSTRAINT DF_CausacionLinea_Impuesto DEFAULT 0,
        Retenciones              decimal(20,4) NOT NULL CONSTRAINT DF_CausacionLinea_Retencion DEFAULT 0,
        Total                    decimal(20,4) NOT NULL,
        CONSTRAINT PK_CausacionServicioLinea PRIMARY KEY CLUSTERED (CausacionServicioLineaId),
        CONSTRAINT UQ_CausacionServicioLinea_Numero UNIQUE (EmpresaId, CausacionServicioId, NumeroLinea),
        CONSTRAINT FK_CausacionServicioLinea_Causacion FOREIGN KEY (EmpresaId, CausacionServicioId) REFERENCES comp.CausacionServicio(EmpresaId, CausacionServicioId),
        CONSTRAINT FK_CausacionServicioLinea_DocumentoLinea FOREIGN KEY (EmpresaId, DocumentoProveedorLineaId) REFERENCES comp.DocumentoProveedorLinea(EmpresaId, DocumentoProveedorLineaId),
        CONSTRAINT CK_CausacionServicioLinea_Valores CHECK (Base >= 0 AND Impuestos >= 0 AND Retenciones >= 0 AND Total >= 0)
    );

    CREATE TABLE inv.SaldoArticuloBodega
    (
        EmpresaId       bigint         NOT NULL,
        BodegaId        bigint         NOT NULL,
        ArticuloId      bigint         NOT NULL,
        Existencia      decimal(20,6)  NOT NULL CONSTRAINT DF_Saldo_Existencia DEFAULT 0,
        ValorTotal      decimal(20,4)  NOT NULL CONSTRAINT DF_Saldo_Valor DEFAULT 0,
        CostoPromedio   decimal(20,8)  NOT NULL CONSTRAINT DF_Saldo_Costo DEFAULT 0,
        UltimoMovimientoId bigint      NULL,
        ActualizadoEnUtc datetime2(7)  NOT NULL CONSTRAINT DF_Saldo_Fecha DEFAULT SYSUTCDATETIME(),
        RowVersion      rowversion     NOT NULL,
        CONSTRAINT PK_SaldoArticuloBodega PRIMARY KEY CLUSTERED (EmpresaId, BodegaId, ArticuloId),
        CONSTRAINT FK_SaldoArticuloBodega_Bodega FOREIGN KEY (EmpresaId, BodegaId) REFERENCES inv.Bodega(EmpresaId, BodegaId),
        CONSTRAINT FK_SaldoArticuloBodega_Articulo FOREIGN KEY (EmpresaId, ArticuloId) REFERENCES inv.Articulo(EmpresaId, ArticuloId),
        CONSTRAINT CK_SaldoArticuloBodega_Costo CHECK (CostoPromedio >= 0)
    );

    CREATE TABLE inv.SaldoArticuloUbicacion
    (
        EmpresaId       bigint         NOT NULL,
        BodegaId        bigint         NOT NULL,
        UbicacionId     bigint         NOT NULL,
        ArticuloId      bigint         NOT NULL,
        Existencia      decimal(20,6)  NOT NULL CONSTRAINT DF_SaldoUbicacion_Existencia DEFAULT 0,
        RowVersion      rowversion     NOT NULL,
        CONSTRAINT PK_SaldoArticuloUbicacion PRIMARY KEY CLUSTERED (EmpresaId, BodegaId, UbicacionId, ArticuloId),
        CONSTRAINT FK_SaldoArticuloUbicacion_Bodega FOREIGN KEY (EmpresaId, BodegaId) REFERENCES inv.Bodega(EmpresaId, BodegaId),
        CONSTRAINT FK_SaldoArticuloUbicacion_Ubicacion FOREIGN KEY (EmpresaId, UbicacionId) REFERENCES inv.Ubicacion(EmpresaId, UbicacionId),
        CONSTRAINT FK_SaldoArticuloUbicacion_Articulo FOREIGN KEY (EmpresaId, ArticuloId) REFERENCES inv.Articulo(EmpresaId, ArticuloId)
    );

    CREATE TABLE inv.SaldoArticuloLoteUbicacion
    (
        EmpresaId       bigint         NOT NULL,
        BodegaId        bigint         NOT NULL,
        UbicacionId     bigint         NOT NULL,
        ArticuloId      bigint         NOT NULL,
        LoteId          bigint         NOT NULL,
        Existencia      decimal(20,6)  NOT NULL CONSTRAINT DF_SaldoLoteUbicacion_Existencia DEFAULT 0,
        RowVersion      rowversion     NOT NULL,
        CONSTRAINT PK_SaldoArticuloLoteUbicacion PRIMARY KEY CLUSTERED (EmpresaId, BodegaId, UbicacionId, ArticuloId, LoteId),
        CONSTRAINT FK_SaldoLoteUbicacion_Bodega FOREIGN KEY (EmpresaId, BodegaId) REFERENCES inv.Bodega(EmpresaId, BodegaId),
        CONSTRAINT FK_SaldoLoteUbicacion_Ubicacion FOREIGN KEY (EmpresaId, UbicacionId) REFERENCES inv.Ubicacion(EmpresaId, UbicacionId),
        CONSTRAINT FK_SaldoLoteUbicacion_Articulo FOREIGN KEY (EmpresaId, ArticuloId) REFERENCES inv.Articulo(EmpresaId, ArticuloId),
        CONSTRAINT FK_SaldoLoteUbicacion_Lote FOREIGN KEY (EmpresaId, LoteId) REFERENCES inv.Lote(EmpresaId, LoteId)
    );

    CREATE TABLE inv.MovimientoInventario
    (
        MovimientoInventarioId bigint           IDENTITY(1,1) NOT NULL,
        EmpresaId               bigint           NOT NULL,
        MovimientoGuid          uniqueidentifier NOT NULL CONSTRAINT DF_Movimiento_Guid DEFAULT NEWSEQUENTIALID(),
        IdempotencyKey          uniqueidentifier NOT NULL,
        BodegaId                bigint           NOT NULL,
        UbicacionId             bigint           NULL,
        ArticuloId              bigint           NOT NULL,
        LoteId                  bigint           NULL,
        PeriodoInventarioId     bigint           NOT NULL,
        FechaMovimiento         datetime2(7)     NOT NULL,
        FechaContable           date             NOT NULL,
        TipoMovimiento          varchar(30)      NOT NULL,
        ModuloOrigen            varchar(30)      NOT NULL,
        TipoDocumentoOrigen     varchar(40)      NOT NULL,
        DocumentoOrigenId       bigint           NOT NULL,
        DocumentoLineaOrigenId  bigint           NULL,
        NumeroDocumento         nvarchar(50)     NOT NULL,
        TerceroId               bigint           NULL,
        CantidadEntrada         decimal(20,6)    NOT NULL CONSTRAINT DF_Movimiento_Entrada DEFAULT 0,
        CantidadSalida          decimal(20,6)    NOT NULL CONSTRAINT DF_Movimiento_Salida DEFAULT 0,
        ExistenciaAnterior      decimal(20,6)    NOT NULL,
        ExistenciaPosterior     decimal(20,6)    NOT NULL,
        CostoUnitarioAnterior   decimal(20,8)    NOT NULL,
        CostoUnitarioMovimiento decimal(20,8)    NOT NULL,
        CostoPromedioPosterior  decimal(20,8)    NOT NULL,
        ValorMovimiento         decimal(20,4)    NOT NULL,
        ValorTotalAnterior      decimal(20,4)    NOT NULL,
        ValorTotalPosterior     decimal(20,4)    NOT NULL,
        MovimientoRelacionadoId bigint           NULL,
        UsuarioId               bigint           NULL,
        CreadoEnUtc             datetime2(7)     NOT NULL CONSTRAINT DF_Movimiento_Fecha DEFAULT SYSUTCDATETIME(),
        CorrelationId           uniqueidentifier NULL,
        CONSTRAINT PK_MovimientoInventario PRIMARY KEY CLUSTERED (MovimientoInventarioId),
        CONSTRAINT UQ_MovimientoInventario_EmpresaId UNIQUE (EmpresaId, MovimientoInventarioId),
        CONSTRAINT UQ_MovimientoInventario_Guid UNIQUE (MovimientoGuid),
        CONSTRAINT UQ_MovimientoInventario_Idempotency UNIQUE (EmpresaId, IdempotencyKey),
        CONSTRAINT FK_MovimientoInventario_Bodega FOREIGN KEY (EmpresaId, BodegaId) REFERENCES inv.Bodega(EmpresaId, BodegaId),
        CONSTRAINT FK_MovimientoInventario_Ubicacion FOREIGN KEY (EmpresaId, UbicacionId) REFERENCES inv.Ubicacion(EmpresaId, UbicacionId),
        CONSTRAINT FK_MovimientoInventario_Articulo FOREIGN KEY (EmpresaId, ArticuloId) REFERENCES inv.Articulo(EmpresaId, ArticuloId),
        CONSTRAINT FK_MovimientoInventario_Lote FOREIGN KEY (EmpresaId, LoteId) REFERENCES inv.Lote(EmpresaId, LoteId),
        CONSTRAINT FK_MovimientoInventario_Periodo FOREIGN KEY (EmpresaId, PeriodoInventarioId) REFERENCES core.PeriodoInventario(EmpresaId, PeriodoInventarioId),
        CONSTRAINT FK_MovimientoInventario_Tercero FOREIGN KEY (EmpresaId, TerceroId) REFERENCES ter.Tercero(EmpresaId, TerceroId),
        CONSTRAINT FK_MovimientoInventario_Usuario FOREIGN KEY (UsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT FK_MovimientoInventario_Relacionado FOREIGN KEY (EmpresaId, MovimientoRelacionadoId) REFERENCES inv.MovimientoInventario(EmpresaId, MovimientoInventarioId),
        CONSTRAINT CK_MovimientoInventario_Cantidades CHECK ((CantidadEntrada > 0 AND CantidadSalida = 0) OR (CantidadSalida > 0 AND CantidadEntrada = 0)),
        CONSTRAINT CK_MovimientoInventario_Valores CHECK (CostoUnitarioAnterior >= 0 AND CostoUnitarioMovimiento >= 0 AND CostoPromedioPosterior >= 0 AND ValorMovimiento >= 0)
    );

    CREATE INDEX IX_MovimientoInventario_Kardex ON inv.MovimientoInventario(EmpresaId, BodegaId, ArticuloId, FechaContable, MovimientoInventarioId)
        INCLUDE (CantidadEntrada, CantidadSalida, ExistenciaPosterior, CostoPromedioPosterior, ValorTotalPosterior, TipoMovimiento, NumeroDocumento);
    CREATE INDEX IX_MovimientoInventario_Origen ON inv.MovimientoInventario(EmpresaId, ModuloOrigen, TipoDocumentoOrigen, DocumentoOrigenId, DocumentoLineaOrigenId);
    CREATE INDEX IX_MovimientoInventario_Periodo ON inv.MovimientoInventario(EmpresaId, PeriodoInventarioId, MovimientoInventarioId);

    INSERT core.SchemaMigration(MigrationId, Descripcion)
    VALUES ('002_inventory_purchasing', N'Maestros, documentos de proveedor, recepciones, servicios, saldos y Kardex');

    COMMIT TRANSACTION;
END;
GO
