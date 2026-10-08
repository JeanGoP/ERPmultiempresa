SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='070_sales_price_approval')
BEGIN
    CREATE TABLE ven.AutorizacionPrecioVenta(
        AutorizacionPrecioVentaId bigint IDENTITY PRIMARY KEY,
        EmpresaId bigint NOT NULL,
        ClienteId bigint NOT NULL,
        OperacionGuid uniqueidentifier NOT NULL,
        FacturaJson nvarchar(max) NOT NULL,
        Huella char(64) NOT NULL,
        ExcepcionesJson nvarchar(max) NOT NULL,
        Motivo nvarchar(500) NOT NULL,
        Estado varchar(12) NOT NULL CONSTRAINT DF_AutorizacionPrecioVenta_Estado DEFAULT 'PENDIENTE',
        SolicitadoPor bigint NOT NULL REFERENCES seg.Usuario(UsuarioId),
        SolicitadoEnUtc datetime2 NOT NULL CONSTRAINT DF_AutorizacionPrecioVenta_Solicitado DEFAULT SYSUTCDATETIME(),
        ResueltoPor bigint NULL REFERENCES seg.Usuario(UsuarioId),
        ResueltoEnUtc datetime2 NULL,
        Respuesta nvarchar(500) NULL,
        FacturaVentaId bigint NULL,
        CONSTRAINT UQ_AutorizacionPrecioVenta_Operacion UNIQUE(EmpresaId,OperacionGuid),
        CONSTRAINT FK_AutorizacionPrecioVenta_Empresa FOREIGN KEY(EmpresaId) REFERENCES core.Empresa(EmpresaId),
        CONSTRAINT FK_AutorizacionPrecioVenta_Cliente FOREIGN KEY(EmpresaId,ClienteId) REFERENCES ter.Tercero(EmpresaId,TerceroId),
        CONSTRAINT FK_AutorizacionPrecioVenta_Factura FOREIGN KEY(EmpresaId,FacturaVentaId) REFERENCES ven.FacturaVenta(EmpresaId,FacturaVentaId),
        CONSTRAINT CK_AutorizacionPrecioVenta_Estado CHECK(Estado IN('PENDIENTE','APROBADA','RECHAZADA','UTILIZADA')),
        CONSTRAINT CK_AutorizacionPrecioVenta_Json CHECK(ISJSON(FacturaJson)=1 AND ISJSON(ExcepcionesJson)=1)
    );
    CREATE INDEX IX_AutorizacionPrecioVenta_Estado ON ven.AutorizacionPrecioVenta(EmpresaId,Estado,AutorizacionPrecioVentaId DESC);
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.AutorizacionPrecioVenta,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.AutorizacionPrecioVenta AFTER INSERT,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.AutorizacionPrecioVenta AFTER UPDATE');
    INSERT core.SchemaMigration(MigrationId,Descripcion)
        VALUES('070_sales_price_approval',N'Solicitudes y aprobación por segundo usuario para descuentos y ventas bajo costo');
END;
COMMIT;
GO
