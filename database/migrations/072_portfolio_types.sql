SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='072_portfolio_types')
BEGIN
    CREATE TABLE ven.TipoCartera(
        TipoCarteraId bigint IDENTITY PRIMARY KEY,
        EmpresaId bigint NOT NULL REFERENCES core.Empresa(EmpresaId),
        Codigo varchar(20) NOT NULL,
        Nombre nvarchar(80) NOT NULL,
        Activo bit NOT NULL CONSTRAINT DF_TipoCartera_Activo DEFAULT 1,
        Version int NOT NULL CONSTRAINT DF_TipoCartera_Version DEFAULT 1,
        CreadoEnUtc datetime2 NOT NULL CONSTRAINT DF_TipoCartera_Creado DEFAULT SYSUTCDATETIME(),
        ActualizadoEnUtc datetime2 NOT NULL CONSTRAINT DF_TipoCartera_Actualizado DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_TipoCartera_EmpresaCodigo UNIQUE(EmpresaId,Codigo),
        CONSTRAINT CK_TipoCartera_Codigo CHECK(LEN(Codigo)>0 AND Codigo NOT LIKE '%[^A-Z0-9_-]%'),
        CONSTRAINT CK_TipoCartera_Nombre CHECK(LEN(LTRIM(RTRIM(Nombre)))>0)
    );
    INSERT ven.TipoCartera(EmpresaId,Codigo,Nombre,Activo)
    SELECT e.EmpresaId,v.Codigo,v.Nombre,v.Activo
    FROM core.Empresa e CROSS JOIN (VALUES
        ('MOTO',N'Motos',CONVERT(bit,1)),
        ('OTROS',N'Otros artículos',CONVERT(bit,1)),
        ('MIXTA',N'Mixta',CONVERT(bit,1)),
        ('SIN_CLASIFICAR',N'Sin clasificar',CONVERT(bit,0))) v(Codigo,Nombre,Activo);
    ALTER TABLE ven.FacturaVenta DROP CONSTRAINT CK_FacturaVenta_ClaseCartera;
    ALTER TABLE ven.FacturaVenta ADD CONSTRAINT FK_FacturaVenta_TipoCartera
        FOREIGN KEY(EmpresaId,ClaseCartera) REFERENCES ven.TipoCartera(EmpresaId,Codigo);
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.TipoCartera,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.TipoCartera AFTER INSERT,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.TipoCartera AFTER UPDATE');
    INSERT seg.Permiso(Codigo,Modulo,Accion,Nombre,EsCritico)
        VALUES('MAESTROS.TIPO_CARTERA.ADMINISTRAR','MAESTROS','ADMINISTRAR',N'Administrar tipos de cartera',1);
    INSERT seg.RolPermiso(RolId,PermisoId)
        SELECT r.RolId,p.PermisoId FROM seg.Rol r CROSS JOIN seg.Permiso p
        WHERE r.Codigo='ADMIN' AND p.Codigo='MAESTROS.TIPO_CARTERA.ADMINISTRAR';
    INSERT core.SchemaMigration(MigrationId,Descripcion)
        VALUES('072_portfolio_types',N'Maestro de tipos de cartera por empresa y clasificación dinámica de facturas');
END;
COMMIT;
GO
