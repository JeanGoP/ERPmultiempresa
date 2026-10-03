SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF SCHEMA_ID(N'cxc') IS NULL EXEC(N'CREATE SCHEMA cxc AUTHORIZATION dbo');
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='062_sales_cash_receipts')
BEGIN
    CREATE TABLE ven.FacturaVenta(
        FacturaVentaId bigint IDENTITY PRIMARY KEY, EmpresaId bigint NOT NULL REFERENCES core.Empresa(EmpresaId),
        OperacionGuid uniqueidentifier NOT NULL, Numero nvarchar(30) NOT NULL, SucursalId bigint NOT NULL,
        ClienteId bigint NOT NULL, FechaContable date NOT NULL, Vencimiento date NOT NULL,
        Base decimal(18,2) NOT NULL, Iva decimal(18,2) NOT NULL, Financiacion decimal(18,2) NOT NULL,
        Total decimal(18,2) NOT NULL, AnticipoAplicado decimal(18,2) NOT NULL DEFAULT 0,
        SaldoPendiente decimal(18,2) NOT NULL, Cuotas int NOT NULL,
        Contenido nvarchar(max) NOT NULL CHECK(ISJSON(Contenido)=1),
        Snapshot nvarchar(max) NULL CHECK(Snapshot IS NULL OR ISJSON(Snapshot)=1),
        CreadoPor bigint NOT NULL REFERENCES seg.Usuario(UsuarioId), CreadoEnUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
        ZeusEstado varchar(20) NOT NULL DEFAULT 'PENDIENTE', ZeusFuente varchar(2) NULL, ZeusDocumento varchar(10) NULL,
        ZeusError nvarchar(2000) NULL, ZeusIntentos int NOT NULL DEFAULT 0, ZeusActualizadoEnUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_FacturaVenta_Operacion UNIQUE(EmpresaId,OperacionGuid),
        CONSTRAINT UQ_FacturaVenta_Numero UNIQUE(EmpresaId,Numero),
        CONSTRAINT UQ_FacturaVenta_Empresa UNIQUE(EmpresaId,FacturaVentaId),
        CONSTRAINT FK_FacturaVenta_Sucursal FOREIGN KEY(EmpresaId,SucursalId) REFERENCES core.Sucursal(EmpresaId,SucursalId),
        CONSTRAINT FK_FacturaVenta_Cliente FOREIGN KEY(EmpresaId,ClienteId) REFERENCES ter.Tercero(EmpresaId,TerceroId),
        CONSTRAINT CK_FacturaVenta_Valores CHECK(Base>=0 AND Iva>=0 AND Financiacion>=0 AND Total>0 AND AnticipoAplicado>=0 AND SaldoPendiente>=0 AND Cuotas>0 AND AnticipoAplicado<=Total AND SaldoPendiente<=Total),
        CONSTRAINT CK_FacturaVenta_Zeus CHECK(ZeusEstado IN('PENDIENTE','ENVIANDO','CONTABILIZADO','RECHAZADO','INCIERTO'))
    );
    CREATE TABLE ven.FacturaVentaLinea(
        FacturaVentaLineaId bigint IDENTITY PRIMARY KEY, EmpresaId bigint NOT NULL, FacturaVentaId bigint NOT NULL,
        ArticuloId bigint NOT NULL, BodegaId bigint NOT NULL, Cantidad decimal(20,6) NOT NULL,
        PrecioConIva decimal(18,2) NOT NULL, TarifaIva decimal(9,4) NOT NULL,
        Base decimal(18,2) NOT NULL, Iva decimal(18,2) NOT NULL, Costo decimal(18,2) NOT NULL DEFAULT 0,
        UnidadesJson nvarchar(max) NULL,
        CONSTRAINT FK_FacturaVentaLinea_Factura FOREIGN KEY(EmpresaId,FacturaVentaId) REFERENCES ven.FacturaVenta(EmpresaId,FacturaVentaId),
        CONSTRAINT FK_FacturaVentaLinea_Articulo FOREIGN KEY(EmpresaId,ArticuloId) REFERENCES inv.Articulo(EmpresaId,ArticuloId),
        CONSTRAINT FK_FacturaVentaLinea_Bodega FOREIGN KEY(EmpresaId,BodegaId) REFERENCES inv.Bodega(EmpresaId,BodegaId),
        CONSTRAINT CK_FacturaVentaLinea_Valores CHECK(Cantidad>0 AND PrecioConIva>0 AND TarifaIva BETWEEN 0 AND 100 AND Base>=0 AND Iva>=0 AND Costo>=0 AND (UnidadesJson IS NULL OR ISJSON(UnidadesJson)=1))
    );
    CREATE TABLE cxc.ReciboCaja(
        ReciboCajaId bigint IDENTITY PRIMARY KEY, EmpresaId bigint NOT NULL REFERENCES core.Empresa(EmpresaId),
        OperacionGuid uniqueidentifier NOT NULL, SucursalId bigint NOT NULL, ClienteId bigint NOT NULL,
        FechaContable date NOT NULL, Tipo varchar(20) NOT NULL, MedioPago varchar(20) NOT NULL,
        Referencia nvarchar(20) NULL, Concepto nvarchar(300) NOT NULL, CuentaContrapartida varchar(16) NULL,
        Total decimal(18,2) NOT NULL, Contenido nvarchar(max) NOT NULL CHECK(ISJSON(Contenido)=1),
        Snapshot nvarchar(max) NULL CHECK(Snapshot IS NULL OR ISJSON(Snapshot)=1),
        CreadoPor bigint NOT NULL REFERENCES seg.Usuario(UsuarioId), CreadoEnUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
        ZeusEstado varchar(20) NOT NULL DEFAULT 'PENDIENTE', ZeusFuente varchar(2) NULL, ZeusDocumento varchar(10) NULL,
        ZeusError nvarchar(2000) NULL, ZeusIntentos int NOT NULL DEFAULT 0, ZeusActualizadoEnUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_ReciboCaja_Operacion UNIQUE(EmpresaId,OperacionGuid),
        CONSTRAINT UQ_ReciboCaja_Empresa UNIQUE(EmpresaId,ReciboCajaId),
        CONSTRAINT FK_ReciboCaja_Sucursal FOREIGN KEY(EmpresaId,SucursalId) REFERENCES core.Sucursal(EmpresaId,SucursalId),
        CONSTRAINT FK_ReciboCaja_Cliente FOREIGN KEY(EmpresaId,ClienteId) REFERENCES ter.Tercero(EmpresaId,TerceroId),
        CONSTRAINT CK_ReciboCaja_Tipo CHECK(Tipo IN('ANTICIPO','CARTERA','NORMAL')),
        CONSTRAINT CK_ReciboCaja_Pago CHECK(MedioPago IN('EFECTIVO','TRANSFERENCIA','CHEQUE')),
        CONSTRAINT CK_ReciboCaja_Valor CHECK(Total>0),
        CONSTRAINT CK_ReciboCaja_Zeus CHECK(ZeusEstado IN('PENDIENTE','ENVIANDO','CONTABILIZADO','RECHAZADO','INCIERTO'))
    );
    CREATE TABLE cxc.ReciboCajaAplicacion(
        EmpresaId bigint NOT NULL, ReciboCajaId bigint NOT NULL, FacturaVentaId bigint NOT NULL,
        Valor decimal(18,2) NOT NULL CHECK(Valor>0),
        CONSTRAINT PK_ReciboCajaAplicacion PRIMARY KEY(EmpresaId,ReciboCajaId,FacturaVentaId),
        CONSTRAINT FK_ReciboCajaAplicacion_Recibo FOREIGN KEY(EmpresaId,ReciboCajaId) REFERENCES cxc.ReciboCaja(EmpresaId,ReciboCajaId),
        CONSTRAINT FK_ReciboCajaAplicacion_Factura FOREIGN KEY(EmpresaId,FacturaVentaId) REFERENCES ven.FacturaVenta(EmpresaId,FacturaVentaId)
    );
    CREATE TABLE cxc.AnticipoCliente(
        EmpresaId bigint NOT NULL, ReciboCajaId bigint NOT NULL, ClienteId bigint NOT NULL,
        Saldo decimal(18,2) NOT NULL CHECK(Saldo>=0),
        CONSTRAINT PK_AnticipoCliente PRIMARY KEY(EmpresaId,ReciboCajaId),
        CONSTRAINT FK_AnticipoCliente_Recibo FOREIGN KEY(EmpresaId,ReciboCajaId) REFERENCES cxc.ReciboCaja(EmpresaId,ReciboCajaId),
        CONSTRAINT FK_AnticipoCliente_Cliente FOREIGN KEY(EmpresaId,ClienteId) REFERENCES ter.Tercero(EmpresaId,TerceroId)
    );
    CREATE TABLE ven.FacturaAnticipo(
        EmpresaId bigint NOT NULL, FacturaVentaId bigint NOT NULL, ReciboCajaId bigint NOT NULL,
        Valor decimal(18,2) NOT NULL CHECK(Valor>0),
        CONSTRAINT PK_FacturaAnticipo PRIMARY KEY(EmpresaId,FacturaVentaId,ReciboCajaId),
        CONSTRAINT FK_FacturaAnticipo_Factura FOREIGN KEY(EmpresaId,FacturaVentaId) REFERENCES ven.FacturaVenta(EmpresaId,FacturaVentaId),
        CONSTRAINT FK_FacturaAnticipo_Recibo FOREIGN KEY(EmpresaId,ReciboCajaId) REFERENCES cxc.ReciboCaja(EmpresaId,ReciboCajaId)
    );
    CREATE INDEX IX_FacturaVenta_Cartera ON ven.FacturaVenta(EmpresaId,ClienteId,SaldoPendiente) INCLUDE(Numero,Vencimiento);
    CREATE INDEX IX_ReciboCaja_Cliente ON cxc.ReciboCaja(EmpresaId,ClienteId,ReciboCajaId DESC);
    DECLARE @Schema sysname,@Table sysname;
    DECLARE tables CURSOR LOCAL FAST_FORWARD FOR
        SELECT SCHEMA_NAME(schema_id),name FROM sys.tables
        WHERE (schema_id=SCHEMA_ID('ven') AND name IN('FacturaVenta','FacturaVentaLinea','FacturaAnticipo'))
           OR (schema_id=SCHEMA_ID('cxc') AND name IN('ReciboCaja','ReciboCajaAplicacion','AnticipoCliente'));
    OPEN tables; FETCH NEXT FROM tables INTO @Schema,@Table;
    WHILE @@FETCH_STATUS=0
    BEGIN
        EXEC('ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON '+@Schema+'.'+@Table+', ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON '+@Schema+'.'+@Table+' AFTER INSERT, ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON '+@Schema+'.'+@Table+' AFTER UPDATE;');
        FETCH NEXT FROM tables INTO @Schema,@Table;
    END;
    CLOSE tables; DEALLOCATE tables;
    INSERT seg.Permiso(Codigo,Modulo,Accion,Nombre,EsCritico) VALUES
      ('VENTAS.FACTURA.CONTABILIZAR','VENTAS','CONTABILIZAR',N'Contabilizar facturas de venta y cartera de clientes',1),
      ('TESORERIA.RECIBO.CONTABILIZAR','TESORERIA','CONTABILIZAR',N'Contabilizar recibos de caja y anticipos de clientes',1);
    DECLARE @AdminRolId bigint=(SELECT RolId FROM seg.Rol WHERE Codigo='ADMIN');
    INSERT seg.RolPermiso(RolId,PermisoId)
      SELECT @AdminRolId,p.PermisoId FROM seg.Permiso p WHERE p.Codigo IN('VENTAS.FACTURA.CONTABILIZAR','TESORERIA.RECIBO.CONTABILIZAR');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('062_sales_cash_receipts',N'Facturas de venta, anticipos y recibos de caja con aplicación de cartera');
END;
COMMIT;
GO
