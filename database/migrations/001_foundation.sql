SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;

IF SCHEMA_ID(N'core') IS NULL EXEC(N'CREATE SCHEMA core AUTHORIZATION dbo');
IF SCHEMA_ID(N'seg') IS NULL EXEC(N'CREATE SCHEMA seg AUTHORIZATION dbo');
IF SCHEMA_ID(N'ter') IS NULL EXEC(N'CREATE SCHEMA ter AUTHORIZATION dbo');
IF SCHEMA_ID(N'inv') IS NULL EXEC(N'CREATE SCHEMA inv AUTHORIZATION dbo');
IF SCHEMA_ID(N'comp') IS NULL EXEC(N'CREATE SCHEMA comp AUTHORIZATION dbo');
IF SCHEMA_ID(N'cost') IS NULL EXEC(N'CREATE SCHEMA cost AUTHORIZATION dbo');
IF SCHEMA_ID(N'audit') IS NULL EXEC(N'CREATE SCHEMA audit AUTHORIZATION dbo');
GO

IF OBJECT_ID(N'core.SchemaMigration', N'U') IS NULL
BEGIN
    CREATE TABLE core.SchemaMigration
    (
        MigrationId       varchar(50)    NOT NULL,
        Descripcion       nvarchar(250)  NOT NULL,
        AplicadaEnUtc     datetime2(7)   NOT NULL CONSTRAINT DF_SchemaMigration_Fecha DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_SchemaMigration PRIMARY KEY CLUSTERED (MigrationId)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM core.SchemaMigration WHERE MigrationId = '001_foundation')
BEGIN
    BEGIN TRANSACTION;

    CREATE TABLE core.Empresa
    (
        EmpresaId             bigint           IDENTITY(1,1) NOT NULL,
        EmpresaGuid           uniqueidentifier NOT NULL CONSTRAINT DF_Empresa_Guid DEFAULT NEWSEQUENTIALID(),
        Codigo                nvarchar(20)     NOT NULL,
        Nit                   nvarchar(20)     NOT NULL,
        DigitoVerificacion    char(1)          NULL,
        RazonSocial           nvarchar(200)    NOT NULL,
        MonedaFuncional       char(3)          NOT NULL CONSTRAINT DF_Empresa_Moneda DEFAULT 'COP',
        ZonaHoraria           nvarchar(80)     NOT NULL CONSTRAINT DF_Empresa_Zona DEFAULT 'America/Bogota',
        MarcoContable         varchar(20)      NOT NULL CONSTRAINT DF_Empresa_Marco DEFAULT 'GRUPO_2',
        Activa                bit              NOT NULL CONSTRAINT DF_Empresa_Activa DEFAULT 1,
        CreadaEnUtc           datetime2(7)     NOT NULL CONSTRAINT DF_Empresa_Creada DEFAULT SYSUTCDATETIME(),
        RowVersion            rowversion       NOT NULL,
        CONSTRAINT PK_Empresa PRIMARY KEY CLUSTERED (EmpresaId),
        CONSTRAINT UQ_Empresa_Guid UNIQUE (EmpresaGuid),
        CONSTRAINT UQ_Empresa_Codigo UNIQUE (Codigo),
        CONSTRAINT CK_Empresa_Marco CHECK (MarcoContable IN ('GRUPO_1','GRUPO_2','GRUPO_3'))
    );

    CREATE TABLE core.EmpresaConfiguracion
    (
        EmpresaId                    bigint       NOT NULL,
        FormulaCosto                 varchar(20)  NOT NULL CONSTRAINT DF_EmpresaConfig_Costo DEFAULT 'PROMEDIO_MOVIL',
        PermiteInventarioNegativo    bit          NOT NULL CONSTRAINT DF_EmpresaConfig_Negativo DEFAULT 0,
        UsaUbicaciones               bit          NOT NULL CONSTRAINT DF_EmpresaConfig_Ubicacion DEFAULT 0,
        RequiereAprobacionAjuste     bit          NOT NULL CONSTRAINT DF_EmpresaConfig_Ajuste DEFAULT 1,
        DecimalesCantidad            tinyint      NOT NULL CONSTRAINT DF_EmpresaConfig_DecCantidad DEFAULT 6,
        DecimalesCostoUnitario       tinyint      NOT NULL CONSTRAINT DF_EmpresaConfig_DecCosto DEFAULT 8,
        ActualizadaEnUtc             datetime2(7) NOT NULL CONSTRAINT DF_EmpresaConfig_Fecha DEFAULT SYSUTCDATETIME(),
        RowVersion                   rowversion   NOT NULL,
        CONSTRAINT PK_EmpresaConfiguracion PRIMARY KEY CLUSTERED (EmpresaId),
        CONSTRAINT FK_EmpresaConfiguracion_Empresa FOREIGN KEY (EmpresaId) REFERENCES core.Empresa(EmpresaId),
        CONSTRAINT CK_EmpresaConfig_Formula CHECK (FormulaCosto IN ('PROMEDIO_MOVIL','PEPS','IDENTIFICACION_ESPECIFICA')),
        CONSTRAINT CK_EmpresaConfig_DecCantidad CHECK (DecimalesCantidad BETWEEN 0 AND 6),
        CONSTRAINT CK_EmpresaConfig_DecCosto CHECK (DecimalesCostoUnitario BETWEEN 0 AND 8)
    );

    CREATE TABLE core.Consecutivo
    (
        EmpresaId          bigint        NOT NULL,
        TipoDocumento      varchar(40)   NOT NULL,
        Prefijo            nvarchar(10)  NOT NULL CONSTRAINT DF_Consecutivo_Prefijo DEFAULT '',
        SiguienteNumero    bigint        NOT NULL CONSTRAINT DF_Consecutivo_Numero DEFAULT 1,
        RowVersion         rowversion    NOT NULL,
        CONSTRAINT PK_Consecutivo PRIMARY KEY CLUSTERED (EmpresaId, TipoDocumento),
        CONSTRAINT FK_Consecutivo_Empresa FOREIGN KEY (EmpresaId) REFERENCES core.Empresa(EmpresaId),
        CONSTRAINT CK_Consecutivo_Numero CHECK (SiguienteNumero > 0)
    );

    CREATE TABLE core.PeriodoInventario
    (
        PeriodoInventarioId   bigint       IDENTITY(1,1) NOT NULL,
        EmpresaId             bigint       NOT NULL,
        Codigo                char(7)      NOT NULL,
        FechaInicio           date         NOT NULL,
        FechaFin              date         NOT NULL,
        Estado                varchar(15)  NOT NULL CONSTRAINT DF_Periodo_Estado DEFAULT 'ABIERTO',
        CerradoEnUtc          datetime2(7) NULL,
        CerradoPorUsuarioId   bigint       NULL,
        MotivoReapertura      nvarchar(500) NULL,
        RowVersion            rowversion   NOT NULL,
        CONSTRAINT PK_PeriodoInventario PRIMARY KEY CLUSTERED (PeriodoInventarioId),
        CONSTRAINT UQ_PeriodoInventario_EmpresaId UNIQUE (EmpresaId, PeriodoInventarioId),
        CONSTRAINT UQ_PeriodoInventario_Codigo UNIQUE (EmpresaId, Codigo),
        CONSTRAINT FK_PeriodoInventario_Empresa FOREIGN KEY (EmpresaId) REFERENCES core.Empresa(EmpresaId),
        CONSTRAINT CK_PeriodoInventario_Fechas CHECK (FechaInicio <= FechaFin),
        CONSTRAINT CK_PeriodoInventario_Estado CHECK (Estado IN ('ABIERTO','EN_CIERRE','CERRADO','REABIERTO','BLOQUEADO'))
    );

    CREATE TABLE seg.Usuario
    (
        UsuarioId       bigint           IDENTITY(1,1) NOT NULL,
        UsuarioGuid     uniqueidentifier NOT NULL CONSTRAINT DF_Usuario_Guid DEFAULT NEWSEQUENTIALID(),
        Correo          nvarchar(254)    NOT NULL,
        NombreCompleto  nvarchar(150)    NOT NULL,
        Activo          bit              NOT NULL CONSTRAINT DF_Usuario_Activo DEFAULT 1,
        CreadoEnUtc     datetime2(7)     NOT NULL CONSTRAINT DF_Usuario_Fecha DEFAULT SYSUTCDATETIME(),
        RowVersion      rowversion       NOT NULL,
        CONSTRAINT PK_Usuario PRIMARY KEY CLUSTERED (UsuarioId),
        CONSTRAINT UQ_Usuario_Guid UNIQUE (UsuarioGuid),
        CONSTRAINT UQ_Usuario_Correo UNIQUE (Correo)
    );

    CREATE TABLE seg.Rol
    (
        RolId        bigint         IDENTITY(1,1) NOT NULL,
        Codigo       varchar(50)    NOT NULL,
        Nombre       nvarchar(100)  NOT NULL,
        CONSTRAINT PK_Rol PRIMARY KEY CLUSTERED (RolId),
        CONSTRAINT UQ_Rol_Codigo UNIQUE (Codigo)
    );

    CREATE TABLE seg.UsuarioEmpresaRol
    (
        EmpresaId    bigint       NOT NULL,
        UsuarioId    bigint       NOT NULL,
        RolId        bigint       NOT NULL,
        Activo       bit          NOT NULL CONSTRAINT DF_UsuarioEmpresaRol_Activo DEFAULT 1,
        AsignadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_UsuarioEmpresaRol_Fecha DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_UsuarioEmpresaRol PRIMARY KEY CLUSTERED (EmpresaId, UsuarioId, RolId),
        CONSTRAINT FK_UsuarioEmpresaRol_Empresa FOREIGN KEY (EmpresaId) REFERENCES core.Empresa(EmpresaId),
        CONSTRAINT FK_UsuarioEmpresaRol_Usuario FOREIGN KEY (UsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT FK_UsuarioEmpresaRol_Rol FOREIGN KEY (RolId) REFERENCES seg.Rol(RolId)
    );

    CREATE TABLE ter.Tercero
    (
        TerceroId       bigint          IDENTITY(1,1) NOT NULL,
        EmpresaId       bigint          NOT NULL,
        TipoIdentificacion varchar(10)   NOT NULL CONSTRAINT DF_Tercero_TipoId DEFAULT 'NIT',
        NumeroIdentificacion nvarchar(30) NOT NULL,
        DigitoVerificacion char(1)       NULL,
        RazonSocial     nvarchar(200)   NOT NULL,
        EsProveedor     bit             NOT NULL CONSTRAINT DF_Tercero_Proveedor DEFAULT 0,
        EsCliente       bit             NOT NULL CONSTRAINT DF_Tercero_Cliente DEFAULT 0,
        Activo          bit             NOT NULL CONSTRAINT DF_Tercero_Activo DEFAULT 1,
        CreadoEnUtc     datetime2(7)    NOT NULL CONSTRAINT DF_Tercero_Fecha DEFAULT SYSUTCDATETIME(),
        RowVersion      rowversion      NOT NULL,
        CONSTRAINT PK_Tercero PRIMARY KEY CLUSTERED (TerceroId),
        CONSTRAINT UQ_Tercero_EmpresaId UNIQUE (EmpresaId, TerceroId),
        CONSTRAINT UQ_Tercero_Identificacion UNIQUE (EmpresaId, TipoIdentificacion, NumeroIdentificacion),
        CONSTRAINT FK_Tercero_Empresa FOREIGN KEY (EmpresaId) REFERENCES core.Empresa(EmpresaId)
    );

    CREATE TABLE audit.Evento
    (
        EventoAuditoriaId  bigint           IDENTITY(1,1) NOT NULL,
        EmpresaId          bigint           NOT NULL,
        EventoGuid         uniqueidentifier NOT NULL CONSTRAINT DF_AuditEvento_Guid DEFAULT NEWSEQUENTIALID(),
        FechaEnUtc         datetime2(7)     NOT NULL CONSTRAINT DF_AuditEvento_Fecha DEFAULT SYSUTCDATETIME(),
        UsuarioId          bigint           NULL,
        Operacion          varchar(80)      NOT NULL,
        Entidad            varchar(100)     NOT NULL,
        EntidadId          nvarchar(100)    NULL,
        DocumentoNumero    nvarchar(50)     NULL,
        Motivo             nvarchar(500)    NULL,
        ValoresAnteriores  nvarchar(max)    NULL,
        ValoresPosteriores nvarchar(max)    NULL,
        AplicacionOrigen   nvarchar(100)    NULL,
        CorrelationId      uniqueidentifier NULL,
        CONSTRAINT PK_AuditEvento PRIMARY KEY CLUSTERED (EventoAuditoriaId),
        CONSTRAINT UQ_AuditEvento_Guid UNIQUE (EventoGuid),
        CONSTRAINT FK_AuditEvento_Empresa FOREIGN KEY (EmpresaId) REFERENCES core.Empresa(EmpresaId),
        CONSTRAINT FK_AuditEvento_Usuario FOREIGN KEY (UsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_AuditEvento_JsonAnterior CHECK (ValoresAnteriores IS NULL OR ISJSON(ValoresAnteriores) = 1),
        CONSTRAINT CK_AuditEvento_JsonPosterior CHECK (ValoresPosteriores IS NULL OR ISJSON(ValoresPosteriores) = 1)
    );

    CREATE INDEX IX_AuditEvento_EmpresaFecha ON audit.Evento(EmpresaId, FechaEnUtc DESC) INCLUDE (Operacion, Entidad, EntidadId, UsuarioId);

    INSERT core.SchemaMigration(MigrationId, Descripcion)
    VALUES ('001_foundation', N'Fundación multiempresa, seguridad, periodos, terceros y auditoría');

    COMMIT TRANSACTION;
END;
GO
