SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;

IF NOT EXISTS (SELECT 1 FROM core.SchemaMigration WHERE MigrationId = '003_costs_controls')
BEGIN
    BEGIN TRANSACTION;

    CREATE TABLE cost.ConceptoCostoAdquisicion
    (
        ConceptoCostoId       bigint         IDENTITY(1,1) NOT NULL,
        EmpresaId             bigint         NOT NULL,
        Codigo                nvarchar(30)   NOT NULL,
        Nombre                nvarchar(120)  NOT NULL,
        Tratamiento           varchar(25)    NOT NULL,
        MetodoDistribucionDefecto varchar(25) NULL,
        RequiereDocumentoSoporte bit         NOT NULL CONSTRAINT DF_ConceptoCosto_Soporte DEFAULT 1,
        Activo                bit            NOT NULL CONSTRAINT DF_ConceptoCosto_Activo DEFAULT 1,
        RowVersion            rowversion     NOT NULL,
        CONSTRAINT PK_ConceptoCosto PRIMARY KEY CLUSTERED (ConceptoCostoId),
        CONSTRAINT UQ_ConceptoCosto_EmpresaId UNIQUE (EmpresaId, ConceptoCostoId),
        CONSTRAINT UQ_ConceptoCosto_Codigo UNIQUE (EmpresaId, Codigo),
        CONSTRAINT FK_ConceptoCosto_Empresa FOREIGN KEY (EmpresaId) REFERENCES core.Empresa(EmpresaId),
        CONSTRAINT CK_ConceptoCosto_Tratamiento CHECK (Tratamiento IN ('CAPITALIZABLE','GASTO','IMPUESTO_RECUPERABLE','IMPUESTO_NO_RECUPERABLE')),
        CONSTRAINT CK_ConceptoCosto_Metodo CHECK (MetodoDistribucionDefecto IS NULL OR MetodoDistribucionDefecto IN ('VALOR_COMPRA','CANTIDAD','PESO','VOLUMEN','VALOR_CANTIDAD','PORCENTAJE_MANUAL','VALOR_MANUAL','COMBINADO'))
    );

    CREATE TABLE cost.DocumentoCostoAdquisicion
    (
        DocumentoCostoId       bigint           IDENTITY(1,1) NOT NULL,
        EmpresaId               bigint           NOT NULL,
        DocumentoCostoGuid      uniqueidentifier NOT NULL CONSTRAINT DF_DocumentoCosto_Guid DEFAULT NEWSEQUENTIALID(),
        ConceptoCostoId         bigint           NOT NULL,
        DocumentoProveedorId    bigint           NULL,
        TerceroId               bigint           NOT NULL,
        NumeroSoporte           nvarchar(50)     NOT NULL,
        FechaDocumento          date             NOT NULL,
        Moneda                  char(3)          NOT NULL CONSTRAINT DF_DocumentoCosto_Moneda DEFAULT 'COP',
        ValorDistribuible       decimal(20,4)    NOT NULL,
        Estado                  varchar(20)      NOT NULL CONSTRAINT DF_DocumentoCosto_Estado DEFAULT 'BORRADOR',
        CreadoPorUsuarioId      bigint           NULL,
        CreadoEnUtc             datetime2(7)     NOT NULL CONSTRAINT DF_DocumentoCosto_Fecha DEFAULT SYSUTCDATETIME(),
        RowVersion              rowversion       NOT NULL,
        CONSTRAINT PK_DocumentoCosto PRIMARY KEY CLUSTERED (DocumentoCostoId),
        CONSTRAINT UQ_DocumentoCosto_EmpresaId UNIQUE (EmpresaId, DocumentoCostoId),
        CONSTRAINT UQ_DocumentoCosto_Guid UNIQUE (DocumentoCostoGuid),
        CONSTRAINT UQ_DocumentoCosto_Soporte UNIQUE (EmpresaId, TerceroId, NumeroSoporte, ConceptoCostoId),
        CONSTRAINT FK_DocumentoCosto_Concepto FOREIGN KEY (EmpresaId, ConceptoCostoId) REFERENCES cost.ConceptoCostoAdquisicion(EmpresaId, ConceptoCostoId),
        CONSTRAINT FK_DocumentoCosto_DocumentoProveedor FOREIGN KEY (EmpresaId, DocumentoProveedorId) REFERENCES comp.DocumentoProveedor(EmpresaId, DocumentoProveedorId),
        CONSTRAINT FK_DocumentoCosto_Tercero FOREIGN KEY (EmpresaId, TerceroId) REFERENCES ter.Tercero(EmpresaId, TerceroId),
        CONSTRAINT FK_DocumentoCosto_Usuario FOREIGN KEY (CreadoPorUsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_DocumentoCosto_Valor CHECK (ValorDistribuible >= 0),
        CONSTRAINT CK_DocumentoCosto_Estado CHECK (Estado IN ('BORRADOR','CALCULADO','APROBADO','APLICADO','REVERTIDO','CANCELADO'))
    );

    CREATE TABLE cost.DistribucionCosto
    (
        DistribucionCostoId     bigint           IDENTITY(1,1) NOT NULL,
        EmpresaId               bigint           NOT NULL,
        DistribucionGuid        uniqueidentifier NOT NULL CONSTRAINT DF_DistribucionCosto_Guid DEFAULT NEWSEQUENTIALID(),
        DocumentoCostoId        bigint           NOT NULL,
        Metodo                  varchar(25)      NOT NULL,
        ValorTotal              decimal(20,4)    NOT NULL,
        BaseTotal               decimal(28,10)   NOT NULL,
        DiferenciaRedondeo      decimal(20,4)    NOT NULL CONSTRAINT DF_DistribucionCosto_Redondeo DEFAULT 0,
        Estado                  varchar(20)      NOT NULL CONSTRAINT DF_DistribucionCosto_Estado DEFAULT 'CALCULADA',
        PoliticaJson            nvarchar(max)    NULL,
        CalculadaPorUsuarioId   bigint           NULL,
        CalculadaEnUtc          datetime2(7)     NOT NULL CONSTRAINT DF_DistribucionCosto_Fecha DEFAULT SYSUTCDATETIME(),
        AplicadaEnUtc           datetime2(7)     NULL,
        RowVersion              rowversion       NOT NULL,
        CONSTRAINT PK_DistribucionCosto PRIMARY KEY CLUSTERED (DistribucionCostoId),
        CONSTRAINT UQ_DistribucionCosto_EmpresaId UNIQUE (EmpresaId, DistribucionCostoId),
        CONSTRAINT UQ_DistribucionCosto_Guid UNIQUE (DistribucionGuid),
        CONSTRAINT FK_DistribucionCosto_Documento FOREIGN KEY (EmpresaId, DocumentoCostoId) REFERENCES cost.DocumentoCostoAdquisicion(EmpresaId, DocumentoCostoId),
        CONSTRAINT FK_DistribucionCosto_Usuario FOREIGN KEY (CalculadaPorUsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_DistribucionCosto_Metodo CHECK (Metodo IN ('VALOR_COMPRA','CANTIDAD','PESO','VOLUMEN','VALOR_CANTIDAD','PORCENTAJE_MANUAL','VALOR_MANUAL','COMBINADO')),
        CONSTRAINT CK_DistribucionCosto_Valores CHECK (ValorTotal >= 0 AND BaseTotal >= 0),
        CONSTRAINT CK_DistribucionCosto_Estado CHECK (Estado IN ('CALCULADA','APROBADA','APLICADA','REVERTIDA')),
        CONSTRAINT CK_DistribucionCosto_Json CHECK (PoliticaJson IS NULL OR ISJSON(PoliticaJson) = 1)
    );

    CREATE TABLE cost.DistribucionCostoLinea
    (
        DistribucionCostoLineaId bigint          IDENTITY(1,1) NOT NULL,
        EmpresaId                bigint          NOT NULL,
        DistribucionCostoId      bigint          NOT NULL,
        RecepcionMercanciaLineaId bigint         NOT NULL,
        BaseDistribucion         decimal(28,10)  NOT NULL,
        PorcentajeAsignado       decimal(12,8)   NOT NULL,
        ValorAsignado            decimal(20,4)   NOT NULL,
        CostoUnitarioAntes       decimal(20,8)   NULL,
        CostoUnitarioDespues     decimal(20,8)   NULL,
        EsLineaAjusteRedondeo    bit             NOT NULL CONSTRAINT DF_DistribucionLinea_Redondeo DEFAULT 0,
        CONSTRAINT PK_DistribucionCostoLinea PRIMARY KEY CLUSTERED (DistribucionCostoLineaId),
        CONSTRAINT UQ_DistribucionCostoLinea UNIQUE (EmpresaId, DistribucionCostoId, RecepcionMercanciaLineaId),
        CONSTRAINT FK_DistribucionCostoLinea_Distribucion FOREIGN KEY (EmpresaId, DistribucionCostoId) REFERENCES cost.DistribucionCosto(EmpresaId, DistribucionCostoId),
        CONSTRAINT FK_DistribucionCostoLinea_Recepcion FOREIGN KEY (EmpresaId, RecepcionMercanciaLineaId) REFERENCES inv.RecepcionMercanciaLinea(EmpresaId, RecepcionMercanciaLineaId),
        CONSTRAINT CK_DistribucionCostoLinea_Valores CHECK (BaseDistribucion >= 0 AND PorcentajeAsignado >= 0 AND PorcentajeAsignado <= 100 AND ValorAsignado >= 0)
    );

    CREATE INDEX IX_DistribucionCostoLinea_Recepcion ON cost.DistribucionCostoLinea(EmpresaId, RecepcionMercanciaLineaId) INCLUDE (ValorAsignado, DistribucionCostoId);

    CREATE TABLE inv.Traslado
    (
        TrasladoId          bigint           IDENTITY(1,1) NOT NULL,
        EmpresaId           bigint           NOT NULL,
        TrasladoGuid        uniqueidentifier NOT NULL CONSTRAINT DF_Traslado_Guid DEFAULT NEWSEQUENTIALID(),
        Numero              nvarchar(50)     NOT NULL,
        BodegaOrigenId      bigint           NOT NULL,
        BodegaTransitoId    bigint           NULL,
        BodegaDestinoId     bigint           NOT NULL,
        FechaSalida         datetime2(7)     NOT NULL,
        FechaRecepcion      datetime2(7)     NULL,
        Estado              varchar(20)      NOT NULL CONSTRAINT DF_Traslado_Estado DEFAULT 'BORRADOR',
        CreadoPorUsuarioId  bigint           NULL,
        RowVersion          rowversion       NOT NULL,
        CONSTRAINT PK_Traslado PRIMARY KEY CLUSTERED (TrasladoId),
        CONSTRAINT UQ_Traslado_EmpresaId UNIQUE (EmpresaId, TrasladoId),
        CONSTRAINT UQ_Traslado_Guid UNIQUE (TrasladoGuid),
        CONSTRAINT UQ_Traslado_Numero UNIQUE (EmpresaId, Numero),
        CONSTRAINT FK_Traslado_Origen FOREIGN KEY (EmpresaId, BodegaOrigenId) REFERENCES inv.Bodega(EmpresaId, BodegaId),
        CONSTRAINT FK_Traslado_Transito FOREIGN KEY (EmpresaId, BodegaTransitoId) REFERENCES inv.Bodega(EmpresaId, BodegaId),
        CONSTRAINT FK_Traslado_Destino FOREIGN KEY (EmpresaId, BodegaDestinoId) REFERENCES inv.Bodega(EmpresaId, BodegaId),
        CONSTRAINT FK_Traslado_Usuario FOREIGN KEY (CreadoPorUsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_Traslado_Bodegas CHECK (BodegaOrigenId <> BodegaDestinoId),
        CONSTRAINT CK_Traslado_Estado CHECK (Estado IN ('BORRADOR','DESPACHADO','EN_TRANSITO','RECIBIDO_PARCIAL','RECIBIDO','REVERTIDO','CANCELADO'))
    );

    CREATE TABLE inv.TrasladoLinea
    (
        TrasladoLineaId bigint         IDENTITY(1,1) NOT NULL,
        EmpresaId       bigint         NOT NULL,
        TrasladoId      bigint         NOT NULL,
        NumeroLinea     int            NOT NULL,
        ArticuloId      bigint         NOT NULL,
        CantidadDespachada decimal(20,6) NOT NULL,
        CantidadRecibida  decimal(20,6) NULL,
        CostoUnitarioSalida decimal(20,8) NULL,
        LoteId          bigint         NULL,
        CONSTRAINT PK_TrasladoLinea PRIMARY KEY CLUSTERED (TrasladoLineaId),
        CONSTRAINT UQ_TrasladoLinea_Numero UNIQUE (EmpresaId, TrasladoId, NumeroLinea),
        CONSTRAINT FK_TrasladoLinea_Traslado FOREIGN KEY (EmpresaId, TrasladoId) REFERENCES inv.Traslado(EmpresaId, TrasladoId),
        CONSTRAINT FK_TrasladoLinea_Articulo FOREIGN KEY (EmpresaId, ArticuloId) REFERENCES inv.Articulo(EmpresaId, ArticuloId),
        CONSTRAINT FK_TrasladoLinea_Lote FOREIGN KEY (EmpresaId, LoteId) REFERENCES inv.Lote(EmpresaId, LoteId),
        CONSTRAINT CK_TrasladoLinea_Cantidades CHECK (CantidadDespachada > 0 AND (CantidadRecibida IS NULL OR CantidadRecibida >= 0))
    );

    CREATE TABLE inv.ConteoFisico
    (
        ConteoFisicoId      bigint           IDENTITY(1,1) NOT NULL,
        EmpresaId           bigint           NOT NULL,
        ConteoGuid          uniqueidentifier NOT NULL CONSTRAINT DF_ConteoFisico_Guid DEFAULT NEWSEQUENTIALID(),
        Numero              nvarchar(50)     NOT NULL,
        BodegaId            bigint           NOT NULL,
        FechaCorte          datetime2(7)     NOT NULL,
        Estado              varchar(20)      NOT NULL CONSTRAINT DF_ConteoFisico_Estado DEFAULT 'PREPARACION',
        CreadoPorUsuarioId  bigint           NULL,
        AprobadoPorUsuarioId bigint          NULL,
        CreadoEnUtc         datetime2(7)     NOT NULL CONSTRAINT DF_ConteoFisico_Fecha DEFAULT SYSUTCDATETIME(),
        RowVersion          rowversion       NOT NULL,
        CONSTRAINT PK_ConteoFisico PRIMARY KEY CLUSTERED (ConteoFisicoId),
        CONSTRAINT UQ_ConteoFisico_EmpresaId UNIQUE (EmpresaId, ConteoFisicoId),
        CONSTRAINT UQ_ConteoFisico_Guid UNIQUE (ConteoGuid),
        CONSTRAINT UQ_ConteoFisico_Numero UNIQUE (EmpresaId, Numero),
        CONSTRAINT FK_ConteoFisico_Bodega FOREIGN KEY (EmpresaId, BodegaId) REFERENCES inv.Bodega(EmpresaId, BodegaId),
        CONSTRAINT FK_ConteoFisico_UsuarioCrea FOREIGN KEY (CreadoPorUsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT FK_ConteoFisico_UsuarioAprueba FOREIGN KEY (AprobadoPorUsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_ConteoFisico_Estado CHECK (Estado IN ('PREPARACION','EN_CONTEO','RECONTEO','EN_REVISION','APROBADO','APLICADO','CANCELADO'))
    );

    CREATE TABLE inv.ConteoFisicoLinea
    (
        ConteoFisicoLineaId bigint         IDENTITY(1,1) NOT NULL,
        EmpresaId           bigint         NOT NULL,
        ConteoFisicoId      bigint         NOT NULL,
        ArticuloId          bigint         NOT NULL,
        UbicacionId         bigint         NULL,
        LoteId              bigint         NULL,
        ExistenciaTeorica   decimal(20,6) NOT NULL,
        CantidadAprobada    decimal(20,6) NULL,
        DiferenciaAprobada  decimal(20,6) NULL,
        CONSTRAINT PK_ConteoFisicoLinea PRIMARY KEY CLUSTERED (ConteoFisicoLineaId),
        CONSTRAINT UQ_ConteoFisicoLinea_EmpresaId UNIQUE (EmpresaId, ConteoFisicoLineaId),
        CONSTRAINT FK_ConteoFisicoLinea_Conteo FOREIGN KEY (EmpresaId, ConteoFisicoId) REFERENCES inv.ConteoFisico(EmpresaId, ConteoFisicoId),
        CONSTRAINT FK_ConteoFisicoLinea_Articulo FOREIGN KEY (EmpresaId, ArticuloId) REFERENCES inv.Articulo(EmpresaId, ArticuloId),
        CONSTRAINT FK_ConteoFisicoLinea_Ubicacion FOREIGN KEY (EmpresaId, UbicacionId) REFERENCES inv.Ubicacion(EmpresaId, UbicacionId),
        CONSTRAINT FK_ConteoFisicoLinea_Lote FOREIGN KEY (EmpresaId, LoteId) REFERENCES inv.Lote(EmpresaId, LoteId)
    );

    CREATE TABLE inv.ConteoCaptura
    (
        ConteoCapturaId      bigint         IDENTITY(1,1) NOT NULL,
        EmpresaId            bigint         NOT NULL,
        ConteoFisicoLineaId  bigint         NOT NULL,
        NumeroConteo         smallint       NOT NULL,
        CantidadContada      decimal(20,6) NOT NULL,
        UsuarioId            bigint         NULL,
        CapturadaEnUtc       datetime2(7)   NOT NULL CONSTRAINT DF_ConteoCaptura_Fecha DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_ConteoCaptura PRIMARY KEY CLUSTERED (ConteoCapturaId),
        CONSTRAINT UQ_ConteoCaptura_Numero UNIQUE (EmpresaId, ConteoFisicoLineaId, NumeroConteo, UsuarioId),
        CONSTRAINT FK_ConteoCaptura_Linea FOREIGN KEY (EmpresaId, ConteoFisicoLineaId) REFERENCES inv.ConteoFisicoLinea(EmpresaId, ConteoFisicoLineaId),
        CONSTRAINT FK_ConteoCaptura_Usuario FOREIGN KEY (UsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_ConteoCaptura_Numero CHECK (NumeroConteo > 0),
        CONSTRAINT CK_ConteoCaptura_Cantidad CHECK (CantidadContada >= 0)
    );

    CREATE TABLE inv.DeterioroInventario
    (
        DeterioroInventarioId bigint          IDENTITY(1,1) NOT NULL,
        EmpresaId             bigint          NOT NULL,
        BodegaId              bigint          NOT NULL,
        ArticuloId            bigint          NOT NULL,
        PeriodoInventarioId   bigint          NOT NULL,
        Tipo                  varchar(20)     NOT NULL,
        CostoHistorico        decimal(20,4)   NOT NULL,
        ValorNetoRealizable   decimal(20,4)   NOT NULL,
        ValorDeterioro        decimal(20,4)   NOT NULL,
        Motivo                nvarchar(500)   NOT NULL,
        DocumentoSoporte      nvarchar(100)   NULL,
        MovimientoRelacionadoId bigint       NULL,
        CreadoPorUsuarioId    bigint          NULL,
        CreadoEnUtc           datetime2(7)    NOT NULL CONSTRAINT DF_Deterioro_Fecha DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_DeterioroInventario PRIMARY KEY CLUSTERED (DeterioroInventarioId),
        CONSTRAINT FK_Deterioro_Bodega FOREIGN KEY (EmpresaId, BodegaId) REFERENCES inv.Bodega(EmpresaId, BodegaId),
        CONSTRAINT FK_Deterioro_Articulo FOREIGN KEY (EmpresaId, ArticuloId) REFERENCES inv.Articulo(EmpresaId, ArticuloId),
        CONSTRAINT FK_Deterioro_Periodo FOREIGN KEY (EmpresaId, PeriodoInventarioId) REFERENCES core.PeriodoInventario(EmpresaId, PeriodoInventarioId),
        CONSTRAINT FK_Deterioro_Movimiento FOREIGN KEY (EmpresaId, MovimientoRelacionadoId) REFERENCES inv.MovimientoInventario(EmpresaId, MovimientoInventarioId),
        CONSTRAINT FK_Deterioro_Usuario FOREIGN KEY (CreadoPorUsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_Deterioro_Tipo CHECK (Tipo IN ('DETERIORO','REVERSA','OBSOLESCENCIA','DANO','PERDIDA','DESTRUCCION')),
        CONSTRAINT CK_Deterioro_Valores CHECK (CostoHistorico >= 0 AND ValorNetoRealizable >= 0 AND ValorDeterioro >= 0)
    );

    INSERT core.SchemaMigration(MigrationId, Descripcion)
    VALUES ('003_costs_controls', N'Costos adicionales, traslados, inventarios físicos y deterioro');

    COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER TRIGGER inv.TR_MovimientoInventario_Inmutable
ON inv.MovimientoInventario
INSTEAD OF UPDATE, DELETE
AS
BEGIN
    THROW 51001, 'El Kardex es inmutable. Registre un movimiento de reversión o ajuste.', 1;
END;
GO

CREATE OR ALTER TRIGGER audit.TR_Evento_Inmutable
ON audit.Evento
INSTEAD OF UPDATE, DELETE
AS
BEGIN
    THROW 51002, 'La auditoría es inmutable.', 1;
END;
GO
