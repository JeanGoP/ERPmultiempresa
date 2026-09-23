SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='059_disbursement_posting')
BEGIN
    CREATE TABLE cxp.EgresoCuentaSucursal(
        EmpresaId bigint NOT NULL, SucursalId bigint NOT NULL, MedioPago varchar(20) NOT NULL,
        Cuenta varchar(16) NOT NULL, Nombre nvarchar(100) NOT NULL, Banco varchar(3) NOT NULL, MonedaZeus varchar(3) NOT NULL,
        Servidor nvarchar(150) NOT NULL, BaseDatos nvarchar(128) NOT NULL,
        Version int NOT NULL DEFAULT 1, ActualizadoPor bigint NOT NULL REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT PK_EgresoCuentaSucursal PRIMARY KEY(EmpresaId,SucursalId,MedioPago),
        CONSTRAINT FK_EgresoCuentaSucursal_Sucursal FOREIGN KEY(EmpresaId,SucursalId) REFERENCES core.Sucursal(EmpresaId,SucursalId),
        CHECK(MedioPago IN('EFECTIVO','TRANSFERENCIA','CHEQUE'))
    );
    CREATE TABLE cxp.Egreso(
        EgresoId bigint IDENTITY PRIMARY KEY, EmpresaId bigint NOT NULL REFERENCES core.Empresa(EmpresaId),
        OperacionGuid uniqueidentifier NOT NULL, SucursalId bigint NOT NULL, TerceroId bigint NOT NULL,
        FechaContable date NOT NULL, Moneda char(3) NOT NULL, Total decimal(18,2) NOT NULL CHECK(Total>0),
        Contenido nvarchar(max) NOT NULL CHECK(ISJSON(Contenido)=1), Huella binary(32) NOT NULL,
        Snapshot nvarchar(max) NOT NULL CHECK(ISJSON(Snapshot)=1),
        CreadoPor bigint NOT NULL REFERENCES seg.Usuario(UsuarioId), CreadoEnUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
        ZeusEstado varchar(20) NOT NULL DEFAULT 'PENDIENTE', ZeusFuente varchar(2) NULL, ZeusDocumento varchar(10) NULL,
        ZeusError nvarchar(2000) NULL, Intentos int NOT NULL DEFAULT 0, ActualizadoEnUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_Egreso_Operacion UNIQUE(EmpresaId,OperacionGuid),
        CONSTRAINT UQ_Egreso_Empresa UNIQUE(EmpresaId,EgresoId),
        CONSTRAINT FK_Egreso_Sucursal FOREIGN KEY(EmpresaId,SucursalId) REFERENCES core.Sucursal(EmpresaId,SucursalId),
        CONSTRAINT FK_Egreso_Tercero FOREIGN KEY(EmpresaId,TerceroId) REFERENCES ter.Tercero(EmpresaId,TerceroId),
        CHECK(ZeusEstado IN('PENDIENTE','ENVIANDO','CONTABILIZADO','RECHAZADO','INCIERTO'))
    );
    CREATE TABLE cxp.EgresoLinea(
        EgresoLineaId bigint IDENTITY PRIMARY KEY, EmpresaId bigint NOT NULL, EgresoId bigint NOT NULL,
        DocumentoPorPagarId bigint NULL, Cuenta varchar(16) NOT NULL, Concepto nvarchar(200) NOT NULL,
        Debito decimal(18,2) NOT NULL DEFAULT 0, Credito decimal(18,2) NOT NULL DEFAULT 0,
        CONSTRAINT FK_EgresoLinea_Egreso FOREIGN KEY(EmpresaId,EgresoId) REFERENCES cxp.Egreso(EmpresaId,EgresoId),
        CONSTRAINT FK_EgresoLinea_Factura FOREIGN KEY(EmpresaId,DocumentoPorPagarId) REFERENCES cxp.DocumentoPorPagar(EmpresaId,DocumentoPorPagarId),
        CHECK((Debito>0 AND Credito=0) OR (Credito>0 AND Debito=0))
    );
    CREATE UNIQUE INDEX UX_EgresoLinea_Factura ON cxp.EgresoLinea(EmpresaId,EgresoId,DocumentoPorPagarId) WHERE DocumentoPorPagarId IS NOT NULL;
    CREATE INDEX IX_Egreso_Cola ON cxp.Egreso(ZeusEstado,ActualizadoEnUtc) INCLUDE(EmpresaId);
    DECLARE @Table sysname;
    DECLARE tables CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM sys.tables WHERE schema_id=SCHEMA_ID('cxp') AND name IN('Egreso','EgresoLinea','EgresoCuentaSucursal');
    OPEN tables; FETCH NEXT FROM tables INTO @Table;
    WHILE @@FETCH_STATUS=0
    BEGIN
        EXEC('ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cxp.'+@Table+', ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cxp.'+@Table+' AFTER INSERT, ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cxp.'+@Table+' AFTER UPDATE;');
        FETCH NEXT FROM tables INTO @Table;
    END;
    CLOSE tables; DEALLOCATE tables;
    INSERT seg.Permiso(Codigo,Modulo,Accion,Nombre,EsCritico) VALUES('TESORERIA.EGRESO.CONTABILIZAR','TESORERIA','CONTABILIZAR',N'Contabilizar egresos y aplicar pagos a proveedores',1);
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('059_disbursement_posting',N'Egresos reales, pagos de cartera, cuentas por sucursal y envío durable a Zeus');
END;
COMMIT;
GO
CREATE OR ALTER TRIGGER cxp.tr_EgresoLinea_Inmutable ON cxp.EgresoLinea AFTER UPDATE,DELETE AS
BEGIN
    IF NOT EXISTS(SELECT 1 FROM deleted) RETURN;
    IF COALESCE(TRY_CONVERT(bit,SESSION_CONTEXT(N'BypassRls')),0)<>1 THROW 52110,'Las líneas contabilizadas de egreso no se editan ni eliminan.',1;
END;
GO
CREATE OR ALTER TRIGGER cxp.tr_Egreso_Inmutable ON cxp.Egreso AFTER UPDATE,DELETE AS
BEGIN
    IF NOT EXISTS(SELECT 1 FROM deleted) RETURN;
    IF COALESCE(TRY_CONVERT(bit,SESSION_CONTEXT(N'BypassRls')),0)=1 RETURN;
    IF NOT EXISTS(SELECT 1 FROM inserted) OR UPDATE(EmpresaId) OR UPDATE(OperacionGuid) OR UPDATE(SucursalId) OR UPDATE(TerceroId) OR UPDATE(FechaContable) OR UPDATE(Moneda) OR UPDATE(Total) OR UPDATE(Contenido) OR UPDATE(Huella) OR UPDATE(Snapshot) OR UPDATE(CreadoPor)
        THROW 52111,'El egreso contabilizado es inmutable. Solo puede cambiar el seguimiento de Zeus.',1;
END;
GO
