SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='058_disbursement_drafts')
BEGIN
    -- Preparación únicamente: no es un pago, no afecta saldos ni tiene consecutivo Zeus.
    CREATE TABLE cxp.EgresoBorrador(
        EgresoBorradorId bigint IDENTITY PRIMARY KEY,
        EmpresaId bigint NOT NULL REFERENCES core.Empresa(EmpresaId),
        OperacionGuid uniqueidentifier NOT NULL,
        SucursalId bigint NOT NULL,
        TerceroId bigint NOT NULL,
        FechaContable date NOT NULL,
        Moneda char(3) NOT NULL,
        Total decimal(18,2) NOT NULL CHECK(Total>0),
        Contenido nvarchar(max) NOT NULL CHECK(ISJSON(Contenido)=1),
        Huella binary(32) NOT NULL,
        Version int NOT NULL DEFAULT 1 CHECK(Version>0),
        CreadoPor bigint NOT NULL REFERENCES seg.Usuario(UsuarioId),
        ActualizadoPor bigint NOT NULL REFERENCES seg.Usuario(UsuarioId),
        CreadoEnUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
        ActualizadoEnUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_EgresoBorrador_Operacion UNIQUE(EmpresaId,OperacionGuid),
        CONSTRAINT FK_EgresoBorrador_Sucursal FOREIGN KEY(EmpresaId,SucursalId) REFERENCES core.Sucursal(EmpresaId,SucursalId),
        CONSTRAINT FK_EgresoBorrador_Tercero FOREIGN KEY(EmpresaId,TerceroId) REFERENCES ter.Tercero(EmpresaId,TerceroId)
    );
    CREATE INDEX IX_EgresoBorrador_Empresa ON cxp.EgresoBorrador(EmpresaId,EgresoBorradorId DESC);
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy
        ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cxp.EgresoBorrador,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cxp.EgresoBorrador AFTER INSERT,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cxp.EgresoBorrador AFTER UPDATE;');
    INSERT seg.Permiso(Codigo,Modulo,Accion,Nombre,EsCritico)
    VALUES('TESORERIA.EGRESO.PREPARAR','TESORERIA','PREPARAR',N'Preparar y consultar borradores de egreso',0);
    -- Sin concesión implícita a usuarios: el administrador asigna el nuevo permiso.
    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('058_disbursement_drafts',N'Borradores de egreso por empresa, versionados y auditados, sin afectar cartera ni Zeus');
END;
COMMIT;
GO
