SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='068_portfolio_refinancing')
BEGIN
    ALTER TABLE ven.FacturaVenta ADD PlanVersion int NOT NULL CONSTRAINT DF_FacturaVenta_PlanVersion DEFAULT 1,
        RefinanciacionEstado varchar(12) NOT NULL CONSTRAINT DF_FacturaVenta_RefinanciacionEstado DEFAULT 'LIBRE',
        RefinanciacionAdicional decimal(18,2) NOT NULL CONSTRAINT DF_FacturaVenta_RefinanciacionAdicional DEFAULT 0;
    ALTER TABLE ven.FacturaVenta DROP CONSTRAINT CK_FacturaVenta_Valores;
    EXEC(N'ALTER TABLE ven.FacturaVenta ADD CONSTRAINT CK_FacturaVenta_Valores CHECK(Base>=0 AND Iva>=0 AND Financiacion>=0 AND Total>0 AND AnticipoAplicado>=0 AND SaldoPendiente>=0 AND Cuotas>0 AND AnticipoAplicado<=Total AND RefinanciacionAdicional>=0 AND SaldoPendiente<=Total+RefinanciacionAdicional)');
    EXEC(N'ALTER TABLE ven.FacturaVenta ADD CONSTRAINT CK_FacturaVenta_Refinanciacion CHECK(RefinanciacionEstado IN(''LIBRE'',''PENDIENTE'',''INCIERTO'') AND PlanVersion>0)');
    ALTER TABLE ven.FacturaVentaCuota ADD PlanVersion int NOT NULL CONSTRAINT DF_FacturaVentaCuota_PlanVersion DEFAULT 1,
        EstadoPlan varchar(14) NOT NULL CONSTRAINT DF_FacturaVentaCuota_EstadoPlan DEFAULT 'ACTIVA';
    ALTER TABLE ven.FacturaVentaCuota DROP CONSTRAINT UQ_FacturaVentaCuota_Numero;
    EXEC(N'ALTER TABLE ven.FacturaVentaCuota ADD CONSTRAINT UQ_FacturaVentaCuota_Numero UNIQUE(EmpresaId,FacturaVentaId,PlanVersion,NumeroCuota)');
    EXEC(N'ALTER TABLE ven.FacturaVentaCuota ADD CONSTRAINT CK_FacturaVentaCuota_Plan CHECK(PlanVersion>0 AND EstadoPlan IN(''ACTIVA'',''REFINANCIADA''))');
    CREATE TABLE ven.RefinanciacionCartera(
        RefinanciacionCarteraId bigint IDENTITY PRIMARY KEY,
        EmpresaId bigint NOT NULL,
        FacturaVentaId bigint NOT NULL,
        OperacionGuid uniqueidentifier NOT NULL,
        SucursalId bigint NOT NULL,
        FechaContable date NOT NULL,
        SaldoAnterior decimal(18,2) NOT NULL,
        NuevoSaldo decimal(18,2) NOT NULL,
        Incremento decimal(18,2) NOT NULL,
        CuentaIngresoZeus varchar(16) NULL,
        CentroCostoZeus varchar(16) NULL,
        Motivo nvarchar(300) NOT NULL,
        PlanAnterior nvarchar(max) NOT NULL,
        PlanNuevo nvarchar(max) NOT NULL,
        Snapshot nvarchar(max) NOT NULL,
        ZeusEstado varchar(20) NOT NULL CONSTRAINT DF_RefinanciacionCartera_Zeus DEFAULT 'PENDIENTE',
        ZeusFuente varchar(2) NULL,
        ZeusDocumento varchar(10) NULL,
        ZeusError nvarchar(2000) NULL,
        ZeusIntentos int NOT NULL CONSTRAINT DF_RefinanciacionCartera_Intentos DEFAULT 0,
        ZeusActualizadoEnUtc datetime2 NOT NULL CONSTRAINT DF_RefinanciacionCartera_Actualizado DEFAULT SYSUTCDATETIME(),
        CreadoPor bigint NOT NULL REFERENCES seg.Usuario(UsuarioId),
        CreadoEnUtc datetime2 NOT NULL CONSTRAINT DF_RefinanciacionCartera_Creado DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_RefinanciacionCartera_Operacion UNIQUE(EmpresaId,OperacionGuid),
        CONSTRAINT FK_RefinanciacionCartera_Factura FOREIGN KEY(EmpresaId,FacturaVentaId) REFERENCES ven.FacturaVenta(EmpresaId,FacturaVentaId),
        CONSTRAINT FK_RefinanciacionCartera_Sucursal FOREIGN KEY(EmpresaId,SucursalId) REFERENCES core.Sucursal(EmpresaId,SucursalId),
        CONSTRAINT CK_RefinanciacionCartera_Valores CHECK(SaldoAnterior>0 AND NuevoSaldo>0 AND Incremento>=0 AND NuevoSaldo=SaldoAnterior+Incremento),
        CONSTRAINT CK_RefinanciacionCartera_Estado CHECK(ZeusEstado IN('PENDIENTE','ENVIANDO','CONTABILIZADO','RECHAZADO','INCIERTO','CANCELADO')),
        CONSTRAINT CK_RefinanciacionCartera_Plan CHECK(ISJSON(PlanAnterior)=1 AND ISJSON(PlanNuevo)=1 AND ISJSON(Snapshot)=1)
    );
    CREATE INDEX IX_RefinanciacionCartera_Factura ON ven.RefinanciacionCartera(EmpresaId,FacturaVentaId,RefinanciacionCarteraId DESC);
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.RefinanciacionCartera,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.RefinanciacionCartera AFTER INSERT,
        ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.RefinanciacionCartera AFTER UPDATE');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('068_portfolio_refinancing',N'Notas de cartera verificadas en Zeus y planes de cuotas versionados');
END;
COMMIT;
GO
