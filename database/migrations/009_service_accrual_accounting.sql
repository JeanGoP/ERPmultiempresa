SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF SCHEMA_ID('cont') IS NULL EXEC('CREATE SCHEMA cont AUTHORIZATION dbo;');
GO

IF NOT EXISTS (SELECT 1 FROM core.SchemaMigration WHERE MigrationId='009_service_accrual_accounting')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;

    CREATE TABLE core.PeriodoContable
    (
        PeriodoContableId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        Codigo nvarchar(20) NOT NULL,
        FechaInicio date NOT NULL,
        FechaFin date NOT NULL,
        Estado varchar(12) NOT NULL CONSTRAINT DF_PeriodoContable_Estado DEFAULT 'ABIERTO',
        CerradoEnUtc datetime2(7) NULL,
        RowVersion rowversion NOT NULL,
        CONSTRAINT PK_PeriodoContable PRIMARY KEY CLUSTERED(PeriodoContableId),
        CONSTRAINT UQ_PeriodoContable_EmpresaId UNIQUE(EmpresaId,PeriodoContableId),
        CONSTRAINT UQ_PeriodoContable_Codigo UNIQUE(EmpresaId,Codigo),
        CONSTRAINT FK_PeriodoContable_Empresa FOREIGN KEY(EmpresaId) REFERENCES core.Empresa(EmpresaId),
        CONSTRAINT CK_PeriodoContable_Fechas CHECK(FechaInicio<=FechaFin),
        CONSTRAINT CK_PeriodoContable_Estado CHECK(Estado IN('ABIERTO','CERRADO','REABIERTO'))
    );

    CREATE TABLE cont.CuentaContable
    (
        CuentaContableId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        Codigo nvarchar(30) NOT NULL,
        Nombre nvarchar(200) NOT NULL,
        Tipo varchar(12) NOT NULL,
        Naturaleza char(1) NOT NULL,
        PermiteMovimiento bit NOT NULL CONSTRAINT DF_Cuenta_PermiteMovimiento DEFAULT 1,
        Activa bit NOT NULL CONSTRAINT DF_Cuenta_Activa DEFAULT 1,
        RowVersion rowversion NOT NULL,
        CONSTRAINT PK_CuentaContable PRIMARY KEY CLUSTERED(CuentaContableId),
        CONSTRAINT UQ_CuentaContable_EmpresaId UNIQUE(EmpresaId,CuentaContableId),
        CONSTRAINT UQ_CuentaContable_Codigo UNIQUE(EmpresaId,Codigo),
        CONSTRAINT FK_CuentaContable_Empresa FOREIGN KEY(EmpresaId) REFERENCES core.Empresa(EmpresaId),
        CONSTRAINT CK_CuentaContable_Tipo CHECK(Tipo IN('ACTIVO','PASIVO','PATRIMONIO','INGRESO','GASTO','COSTO','ORDEN')),
        CONSTRAINT CK_CuentaContable_Naturaleza CHECK(Naturaleza IN('D','C'))
    );

    CREATE TABLE cont.ComprobanteContable
    (
        ComprobanteContableId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        ComprobanteGuid uniqueidentifier NOT NULL CONSTRAINT DF_Comprobante_Guid DEFAULT NEWSEQUENTIALID(),
        IdempotencyKey uniqueidentifier NOT NULL,
        Numero nvarchar(50) NOT NULL,
        FechaContable date NOT NULL,
        PeriodoContableId bigint NOT NULL,
        TipoDocumentoOrigen varchar(40) NOT NULL,
        DocumentoOrigenId bigint NOT NULL,
        TerceroId bigint NULL,
        Concepto nvarchar(500) NOT NULL,
        TotalDebito decimal(20,4) NOT NULL,
        TotalCredito decimal(20,4) NOT NULL,
        Estado varchar(15) NOT NULL CONSTRAINT DF_Comprobante_Estado DEFAULT 'CONTABILIZADO',
        UsuarioId bigint NULL,
        CreadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_Comprobante_Fecha DEFAULT SYSUTCDATETIME(),
        CorrelationId uniqueidentifier NULL,
        CONSTRAINT PK_ComprobanteContable PRIMARY KEY CLUSTERED(ComprobanteContableId),
        CONSTRAINT UQ_ComprobanteContable_EmpresaId UNIQUE(EmpresaId,ComprobanteContableId),
        CONSTRAINT UQ_ComprobanteContable_Guid UNIQUE(ComprobanteGuid),
        CONSTRAINT UQ_ComprobanteContable_Idempotency UNIQUE(EmpresaId,IdempotencyKey),
        CONSTRAINT UQ_ComprobanteContable_Numero UNIQUE(EmpresaId,Numero),
        CONSTRAINT UQ_ComprobanteContable_Origen UNIQUE(EmpresaId,TipoDocumentoOrigen,DocumentoOrigenId),
        CONSTRAINT FK_ComprobanteContable_Periodo FOREIGN KEY(EmpresaId,PeriodoContableId) REFERENCES core.PeriodoContable(EmpresaId,PeriodoContableId),
        CONSTRAINT FK_ComprobanteContable_Tercero FOREIGN KEY(EmpresaId,TerceroId) REFERENCES ter.Tercero(EmpresaId,TerceroId),
        CONSTRAINT FK_ComprobanteContable_Usuario FOREIGN KEY(UsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_ComprobanteContable_Totales CHECK(TotalDebito>=0 AND TotalCredito>=0 AND TotalDebito=TotalCredito),
        CONSTRAINT CK_ComprobanteContable_Estado CHECK(Estado IN('CONTABILIZADO','REVERTIDO'))
    );

    CREATE TABLE cont.ComprobanteContableLinea
    (
        ComprobanteContableLineaId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        ComprobanteContableId bigint NOT NULL,
        NumeroLinea int NOT NULL,
        CuentaContableId bigint NOT NULL,
        TerceroId bigint NULL,
        Descripcion nvarchar(500) NOT NULL,
        Debito decimal(20,4) NOT NULL CONSTRAINT DF_ComprobanteLinea_Debito DEFAULT 0,
        Credito decimal(20,4) NOT NULL CONSTRAINT DF_ComprobanteLinea_Credito DEFAULT 0,
        CentroCostoCodigo nvarchar(50) NULL,
        ProyectoCodigo nvarchar(50) NULL,
        CONSTRAINT PK_ComprobanteContableLinea PRIMARY KEY CLUSTERED(ComprobanteContableLineaId),
        CONSTRAINT UQ_ComprobanteContableLinea_Numero UNIQUE(EmpresaId,ComprobanteContableId,NumeroLinea),
        CONSTRAINT FK_ComprobanteContableLinea_Comprobante FOREIGN KEY(EmpresaId,ComprobanteContableId) REFERENCES cont.ComprobanteContable(EmpresaId,ComprobanteContableId),
        CONSTRAINT FK_ComprobanteContableLinea_Cuenta FOREIGN KEY(EmpresaId,CuentaContableId) REFERENCES cont.CuentaContable(EmpresaId,CuentaContableId),
        CONSTRAINT FK_ComprobanteContableLinea_Tercero FOREIGN KEY(EmpresaId,TerceroId) REFERENCES ter.Tercero(EmpresaId,TerceroId),
        CONSTRAINT CK_ComprobanteContableLinea_Valor CHECK((Debito>0 AND Credito=0) OR (Credito>0 AND Debito=0))
    );

    ALTER TABLE comp.CausacionServicio ADD PeriodoContableId bigint NULL,ComprobanteContableId bigint NULL,ContabilizadoEnUtc datetime2(7) NULL;
    ALTER TABLE comp.CausacionServicio ADD CONSTRAINT FK_CausacionServicio_PeriodoContable FOREIGN KEY(EmpresaId,PeriodoContableId) REFERENCES core.PeriodoContable(EmpresaId,PeriodoContableId);
    ALTER TABLE comp.CausacionServicio ADD CONSTRAINT FK_CausacionServicio_Comprobante FOREIGN KEY(EmpresaId,ComprobanteContableId) REFERENCES cont.ComprobanteContable(EmpresaId,ComprobanteContableId);

    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.PeriodoContable;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.PeriodoContable AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.PeriodoContable AFTER UPDATE;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cont.CuentaContable;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cont.CuentaContable AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cont.CuentaContable AFTER UPDATE;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cont.ComprobanteContable;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cont.ComprobanteContable AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cont.ComprobanteContableLinea;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cont.ComprobanteContableLinea AFTER INSERT;');

    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('009_service_accrual_accounting',N'Plan de cuentas, comprobantes balanceados y causación de servicios');
    COMMIT TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO

CREATE OR ALTER TRIGGER cont.TR_ComprobanteContable_Inmutable ON cont.ComprobanteContable AFTER UPDATE,DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS(SELECT 1 FROM deleted) THROW 51600,'Un comprobante contabilizado es inmutable; use reversión.',1;
END;
GO

CREATE OR ALTER TRIGGER cont.TR_ComprobanteContableLinea_Inmutable ON cont.ComprobanteContableLinea AFTER UPDATE,DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS(SELECT 1 FROM deleted) THROW 51601,'Las líneas de un comprobante contabilizado son inmutables.',1;
END;
GO

CREATE OR ALTER PROCEDURE comp.usp_ContabilizarCausacionServicio
    @EmpresaId bigint,
    @CausacionServicioId bigint,
    @PeriodoContableId bigint,
    @CuentaImpuestoCodigo nvarchar(30)=NULL,
    @CuentaRetencionCodigo nvarchar(30)=NULL,
    @CuentaPorPagarCodigo nvarchar(30),
    @UsuarioId bigint=NULL,
    @CorrelationId uniqueidentifier=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @CorrelationId IS NULL SET @CorrelationId=NEWID();
    BEGIN TRANSACTION;

    DECLARE @Numero nvarchar(50),@DocumentoProveedorId bigint,@TerceroId bigint,@FechaContable date,@Estado varchar(15),@ComprobanteId bigint;
    SELECT @Numero=Numero,@DocumentoProveedorId=DocumentoProveedorId,@TerceroId=TerceroId,@FechaContable=FechaContable,@Estado=Estado,@ComprobanteId=ComprobanteContableId
    FROM comp.CausacionServicio WITH(UPDLOCK,HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND CausacionServicioId=@CausacionServicioId;
    IF @Estado IS NULL THROW 51610,'La causación no existe o no pertenece a la empresa.',1;
    IF @Estado='CONTABILIZADA'
    BEGIN
        COMMIT TRANSACTION;
        SELECT @CausacionServicioId AS CausacionServicioId,@ComprobanteId AS ComprobanteContableId,@Estado AS Estado,CAST(1 AS bit) AS YaExistia;
        RETURN;
    END;
    IF @Estado NOT IN('BORRADOR','VALIDADA') THROW 51611,'La causación no puede contabilizarse en su estado actual.',1;
    IF NOT EXISTS(SELECT 1 FROM core.PeriodoContable WHERE EmpresaId=@EmpresaId AND PeriodoContableId=@PeriodoContableId AND Estado IN('ABIERTO','REABIERTO') AND @FechaContable BETWEEN FechaInicio AND FechaFin)
        THROW 51612,'El periodo contable está cerrado o no corresponde a la fecha.',1;
    IF NOT EXISTS(SELECT 1 FROM comp.CausacionServicioLinea WHERE EmpresaId=@EmpresaId AND CausacionServicioId=@CausacionServicioId)
        THROW 51613,'La causación no contiene líneas.',1;
    IF EXISTS(SELECT 1 FROM comp.CausacionServicioLinea WHERE EmpresaId=@EmpresaId AND CausacionServicioId=@CausacionServicioId AND NULLIF(CuentaContableCodigo,N'') IS NULL)
        THROW 51614,'Todas las líneas de servicio requieren cuenta contable.',1;

    DECLARE @CuentaPorPagarId bigint=(SELECT CuentaContableId FROM cont.CuentaContable WHERE EmpresaId=@EmpresaId AND Codigo=@CuentaPorPagarCodigo AND Activa=1 AND PermiteMovimiento=1);
    DECLARE @CuentaImpuestoId bigint=(SELECT CuentaContableId FROM cont.CuentaContable WHERE EmpresaId=@EmpresaId AND Codigo=@CuentaImpuestoCodigo AND Activa=1 AND PermiteMovimiento=1);
    DECLARE @CuentaRetencionId bigint=(SELECT CuentaContableId FROM cont.CuentaContable WHERE EmpresaId=@EmpresaId AND Codigo=@CuentaRetencionCodigo AND Activa=1 AND PermiteMovimiento=1);
    IF @CuentaPorPagarId IS NULL THROW 51615,'La cuenta por pagar no existe, está inactiva o no recibe movimientos.',1;
    IF EXISTS(SELECT 1 FROM comp.CausacionServicioLinea WHERE EmpresaId=@EmpresaId AND CausacionServicioId=@CausacionServicioId AND Impuestos>0) AND @CuentaImpuestoId IS NULL
        THROW 51616,'La causación tiene impuestos y requiere una cuenta de impuesto descontable válida.',1;
    IF EXISTS(SELECT 1 FROM comp.CausacionServicioLinea WHERE EmpresaId=@EmpresaId AND CausacionServicioId=@CausacionServicioId AND Retenciones>0) AND @CuentaRetencionId IS NULL
        THROW 51617,'La causación tiene retenciones y requiere una cuenta de retención válida.',1;
    IF EXISTS
    (
        SELECT 1 FROM comp.CausacionServicioLinea l
        LEFT JOIN cont.CuentaContable c ON c.EmpresaId=l.EmpresaId AND c.Codigo=l.CuentaContableCodigo AND c.Activa=1 AND c.PermiteMovimiento=1
        WHERE l.EmpresaId=@EmpresaId AND l.CausacionServicioId=@CausacionServicioId AND c.CuentaContableId IS NULL
    ) THROW 51618,'Una cuenta de gasto de las líneas no existe, está inactiva o no recibe movimientos.',1;

    DECLARE @Base decimal(20,4)=(SELECT SUM(Base) FROM comp.CausacionServicioLinea WHERE EmpresaId=@EmpresaId AND CausacionServicioId=@CausacionServicioId);
    DECLARE @Impuestos decimal(20,4)=(SELECT SUM(Impuestos) FROM comp.CausacionServicioLinea WHERE EmpresaId=@EmpresaId AND CausacionServicioId=@CausacionServicioId);
    DECLARE @Retenciones decimal(20,4)=(SELECT SUM(Retenciones) FROM comp.CausacionServicioLinea WHERE EmpresaId=@EmpresaId AND CausacionServicioId=@CausacionServicioId);
    DECLARE @PorPagar decimal(20,4)=@Base+@Impuestos-@Retenciones;
    IF @PorPagar<0 THROW 51619,'Las retenciones no pueden superar la base más impuestos.',1;

    INSERT cont.ComprobanteContable(EmpresaId,IdempotencyKey,Numero,FechaContable,PeriodoContableId,TipoDocumentoOrigen,DocumentoOrigenId,TerceroId,Concepto,TotalDebito,TotalCredito,UsuarioId,CorrelationId)
    VALUES(@EmpresaId,(SELECT CausacionGuid FROM comp.CausacionServicio WHERE EmpresaId=@EmpresaId AND CausacionServicioId=@CausacionServicioId),CONCAT('CAU-',@Numero),@FechaContable,@PeriodoContableId,'CAUSACION_SERVICIO',@CausacionServicioId,@TerceroId,CONCAT(N'Causación de servicios ',@Numero),@Base+@Impuestos,@PorPagar+@Retenciones,@UsuarioId,@CorrelationId);
    SET @ComprobanteId=SCOPE_IDENTITY();

    INSERT cont.ComprobanteContableLinea(EmpresaId,ComprobanteContableId,NumeroLinea,CuentaContableId,TerceroId,Descripcion,Debito,Credito,CentroCostoCodigo,ProyectoCodigo)
    SELECT @EmpresaId,@ComprobanteId,ROW_NUMBER() OVER(ORDER BY l.NumeroLinea),c.CuentaContableId,@TerceroId,l.Descripcion,l.Base,0,s.CentroCostoCodigo,s.ProyectoCodigo
    FROM comp.CausacionServicioLinea l
    JOIN cont.CuentaContable c ON c.EmpresaId=l.EmpresaId AND c.Codigo=l.CuentaContableCodigo
    JOIN comp.CausacionServicio s ON s.EmpresaId=l.EmpresaId AND s.CausacionServicioId=l.CausacionServicioId
    WHERE l.EmpresaId=@EmpresaId AND l.CausacionServicioId=@CausacionServicioId AND l.Base>0;

    DECLARE @SiguienteLinea int=(SELECT COUNT(*)+1 FROM cont.ComprobanteContableLinea WHERE EmpresaId=@EmpresaId AND ComprobanteContableId=@ComprobanteId);
    IF @Impuestos>0
    BEGIN
        INSERT cont.ComprobanteContableLinea(EmpresaId,ComprobanteContableId,NumeroLinea,CuentaContableId,TerceroId,Descripcion,Debito,Credito)
        VALUES(@EmpresaId,@ComprobanteId,@SiguienteLinea,@CuentaImpuestoId,@TerceroId,N'Impuestos descontables',@Impuestos,0);
        SET @SiguienteLinea+=1;
    END;
    IF @Retenciones>0
    BEGIN
        INSERT cont.ComprobanteContableLinea(EmpresaId,ComprobanteContableId,NumeroLinea,CuentaContableId,TerceroId,Descripcion,Debito,Credito)
        VALUES(@EmpresaId,@ComprobanteId,@SiguienteLinea,@CuentaRetencionId,@TerceroId,N'Retenciones practicadas',0,@Retenciones);
        SET @SiguienteLinea+=1;
    END;
    IF @PorPagar>0
        INSERT cont.ComprobanteContableLinea(EmpresaId,ComprobanteContableId,NumeroLinea,CuentaContableId,TerceroId,Descripcion,Debito,Credito)
        VALUES(@EmpresaId,@ComprobanteId,@SiguienteLinea,@CuentaPorPagarId,@TerceroId,N'Cuenta por pagar al proveedor',0,@PorPagar);

    UPDATE comp.CausacionServicio SET Estado='CONTABILIZADA',PeriodoContableId=@PeriodoContableId,ComprobanteContableId=@ComprobanteId,ContabilizadoEnUtc=SYSUTCDATETIME()
    WHERE EmpresaId=@EmpresaId AND CausacionServicioId=@CausacionServicioId;

    IF NOT EXISTS(SELECT 1 FROM inv.RecepcionMercancia WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId AND Estado<>'CONTABILIZADA')
       AND NOT EXISTS(SELECT 1 FROM comp.CausacionServicio WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId AND Estado<>'CONTABILIZADA')
        UPDATE comp.DocumentoProveedor SET Estado='CONTABILIZADO' WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId AND Estado='VALIDADO';

    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresPosteriores,AplicacionOrigen,CorrelationId)
    VALUES(@EmpresaId,@UsuarioId,'CAUSACION_CONTABILIZADA','comp.CausacionServicio',CONVERT(nvarchar(100),@CausacionServicioId),@Numero,
           CONCAT(N'{"comprobanteId":',@ComprobanteId,N',"debito":',CONVERT(varchar(50),@Base+@Impuestos),N',"credito":',CONVERT(varchar(50),@PorPagar+@Retenciones),N'}'),'COMPRAS',@CorrelationId);

    COMMIT TRANSACTION;
    SELECT @CausacionServicioId AS CausacionServicioId,@ComprobanteId AS ComprobanteContableId,CAST('CONTABILIZADA' AS varchar(15)) AS Estado,CAST(0 AS bit) AS YaExistia;
END;
GO
