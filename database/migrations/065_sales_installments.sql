SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='065_sales_installments')
BEGIN
    ALTER TABLE ven.FacturaVenta ADD FrecuenciaCuotas varchar(20) NULL;
    CREATE TABLE ven.FacturaVentaCuota(
        FacturaVentaCuotaId bigint IDENTITY PRIMARY KEY,
        EmpresaId bigint NOT NULL,
        FacturaVentaId bigint NOT NULL,
        NumeroCuota int NOT NULL,
        FechaVencimiento date NOT NULL,
        ValorOriginal decimal(18,2) NOT NULL,
        SaldoPendiente decimal(18,2) NOT NULL,
        CONSTRAINT UQ_FacturaVentaCuota_Empresa UNIQUE(EmpresaId,FacturaVentaCuotaId),
        CONSTRAINT UQ_FacturaVentaCuota_Numero UNIQUE(EmpresaId,FacturaVentaId,NumeroCuota),
        CONSTRAINT FK_FacturaVentaCuota_Factura FOREIGN KEY(EmpresaId,FacturaVentaId) REFERENCES ven.FacturaVenta(EmpresaId,FacturaVentaId),
        CONSTRAINT CK_FacturaVentaCuota_Valor CHECK(NumeroCuota>0 AND ValorOriginal>0 AND SaldoPendiente>=0 AND SaldoPendiente<=ValorOriginal)
    );
    CREATE INDEX IX_FacturaVentaCuota_Cobro ON ven.FacturaVentaCuota(EmpresaId,FacturaVentaId,SaldoPendiente,FechaVencimiento);
    ALTER TABLE cxc.ReciboCajaAplicacion DROP CONSTRAINT PK_ReciboCajaAplicacion;
    ALTER TABLE cxc.ReciboCajaAplicacion ADD ReciboCajaAplicacionId bigint IDENTITY NOT NULL,
        FacturaVentaCuotaId bigint NULL;
    EXEC(N'ALTER TABLE cxc.ReciboCajaAplicacion ADD CONSTRAINT PK_ReciboCajaAplicacion PRIMARY KEY(ReciboCajaAplicacionId)');
    EXEC(N'ALTER TABLE cxc.ReciboCajaAplicacion ADD CONSTRAINT FK_ReciboCajaAplicacion_Cuota
        FOREIGN KEY(EmpresaId,FacturaVentaCuotaId) REFERENCES ven.FacturaVentaCuota(EmpresaId,FacturaVentaCuotaId)');
    EXEC(N'CREATE UNIQUE INDEX UX_ReciboCajaAplicacion_Cuota ON cxc.ReciboCajaAplicacion(EmpresaId,ReciboCajaId,FacturaVentaCuotaId)
        WHERE FacturaVentaCuotaId IS NOT NULL');
    EXEC(N'CREATE UNIQUE INDEX UX_ReciboCajaAplicacion_Legado ON cxc.ReciboCajaAplicacion(EmpresaId,ReciboCajaId,FacturaVentaId)
        WHERE FacturaVentaCuotaId IS NULL');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.FacturaVentaCuota,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.FacturaVentaCuota AFTER INSERT,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.FacturaVentaCuota AFTER UPDATE');
    INSERT core.SchemaMigration(MigrationId,Descripcion)
        VALUES('065_sales_installments',N'Calendario de cuotas de ventas y recaudo por vencimiento');
END;
COMMIT;
GO
