SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='063_sales_concepts')
BEGIN
    CREATE TABLE ven.ConceptoVenta(
        ConceptoVentaId bigint IDENTITY PRIMARY KEY,
        EmpresaId bigint NOT NULL REFERENCES core.Empresa(EmpresaId),
        Codigo varchar(30) NOT NULL,
        Nombre nvarchar(120) NOT NULL,
        CuentaIngresoZeus varchar(16) NOT NULL,
        ServidorZeus nvarchar(255) NOT NULL,
        BaseDatosZeus sysname NOT NULL,
        Activo bit NOT NULL DEFAULT 1,
        Version int NOT NULL DEFAULT 1,
        CreadoPor bigint NOT NULL REFERENCES seg.Usuario(UsuarioId),
        CreadoEnUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
        ActualizadoEnUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_ConceptoVenta_EmpresaId UNIQUE(EmpresaId,ConceptoVentaId),
        CONSTRAINT UQ_ConceptoVenta_Codigo UNIQUE(EmpresaId,Codigo),
        CONSTRAINT CK_ConceptoVenta_Codigo CHECK(LEN(Codigo)>0 AND Codigo NOT LIKE '%[^A-Z0-9_-]%'),
        CONSTRAINT CK_ConceptoVenta_Cuenta CHECK(LEN(CuentaIngresoZeus)>0)
    );
    CREATE TABLE ven.FacturaVentaConcepto(
        FacturaVentaConceptoId bigint IDENTITY PRIMARY KEY,
        EmpresaId bigint NOT NULL,
        FacturaVentaId bigint NOT NULL,
        ConceptoVentaId bigint NOT NULL,
        Codigo varchar(30) NOT NULL,
        Nombre nvarchar(120) NOT NULL,
        CuentaIngresoZeus varchar(16) NOT NULL,
        Valor decimal(18,2) NOT NULL,
        CONSTRAINT FK_FacturaVentaConcepto_Factura FOREIGN KEY(EmpresaId,FacturaVentaId) REFERENCES ven.FacturaVenta(EmpresaId,FacturaVentaId),
        CONSTRAINT FK_FacturaVentaConcepto_Concepto FOREIGN KEY(EmpresaId,ConceptoVentaId) REFERENCES ven.ConceptoVenta(EmpresaId,ConceptoVentaId),
        CONSTRAINT CK_FacturaVentaConcepto_Valor CHECK(Valor>0)
    );
    ALTER TABLE ven.FacturaVenta ADD ConceptosTotal decimal(18,2) NOT NULL CONSTRAINT DF_FacturaVenta_ConceptosTotal DEFAULT 0;
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.ConceptoVenta,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.ConceptoVenta AFTER INSERT,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.ConceptoVenta AFTER UPDATE');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.FacturaVentaConcepto,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.FacturaVentaConcepto AFTER INSERT,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.FacturaVentaConcepto AFTER UPDATE');
    INSERT seg.Permiso(Codigo,Modulo,Accion,Nombre,EsCritico)
        VALUES('MAESTROS.CONCEPTO_VENTA.ADMINISTRAR','MAESTROS','ADMINISTRAR',N'Administrar conceptos de venta y sus cuentas de Zeus',1);
    INSERT seg.RolPermiso(RolId,PermisoId)
        SELECT r.RolId,p.PermisoId FROM seg.Rol r CROSS JOIN seg.Permiso p
        WHERE r.Codigo='ADMIN' AND p.Codigo='MAESTROS.CONCEPTO_VENTA.ADMINISTRAR';
    INSERT core.SchemaMigration(MigrationId,Descripcion)
        VALUES('063_sales_concepts',N'Maestro de conceptos de venta y detalle contable por factura');
END;
COMMIT;
GO
