SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF SCHEMA_ID(N'cxp') IS NULL EXEC(N'CREATE SCHEMA cxp AUTHORIZATION dbo;');
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='043_supplier_accounts_payable')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;

    CREATE TABLE cxp.DocumentoPorPagar
    (
        DocumentoPorPagarId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        DocumentoProveedorId bigint NOT NULL,
        TerceroId bigint NOT NULL,
        FechaReconocimiento date NOT NULL,
        FechaDocumento date NOT NULL,
        FechaVencimiento date NOT NULL,
        Moneda char(3) NOT NULL,
        ValorOriginal decimal(20,4) NOT NULL,
        SaldoPendiente decimal(20,4) NOT NULL,
        Estado varchar(12) NOT NULL CONSTRAINT DF_DocumentoPorPagar_Estado DEFAULT 'ABIERTA',
        ReconocidoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_DocumentoPorPagar_Reconocido DEFAULT SYSUTCDATETIME(),
        ActualizadoEnUtc datetime2(7) NULL,
        RowVersion rowversion NOT NULL,
        CONSTRAINT PK_DocumentoPorPagar PRIMARY KEY CLUSTERED(DocumentoPorPagarId),
        CONSTRAINT UQ_DocumentoPorPagar_EmpresaId UNIQUE(EmpresaId,DocumentoPorPagarId),
        CONSTRAINT UQ_DocumentoPorPagar_Origen UNIQUE(EmpresaId,DocumentoProveedorId),
        CONSTRAINT FK_DocumentoPorPagar_Empresa FOREIGN KEY(EmpresaId) REFERENCES core.Empresa(EmpresaId),
        CONSTRAINT FK_DocumentoPorPagar_Documento FOREIGN KEY(EmpresaId,DocumentoProveedorId) REFERENCES comp.DocumentoProveedor(EmpresaId,DocumentoProveedorId),
        CONSTRAINT FK_DocumentoPorPagar_Tercero FOREIGN KEY(EmpresaId,TerceroId) REFERENCES ter.Tercero(EmpresaId,TerceroId),
        CONSTRAINT CK_DocumentoPorPagar_Valores CHECK(ValorOriginal>0 AND SaldoPendiente>=0 AND SaldoPendiente<=ValorOriginal),
        CONSTRAINT CK_DocumentoPorPagar_Estado CHECK(Estado IN('ABIERTA','PARCIAL','PAGADA','ANULADA'))
    );

    CREATE INDEX IX_DocumentoPorPagar_Proveedor
        ON cxp.DocumentoPorPagar(EmpresaId,TerceroId,Estado,FechaVencimiento)
        INCLUDE(DocumentoProveedorId,ValorOriginal,SaldoPendiente,Moneda);

    CREATE TABLE cxp.MovimientoProveedor
    (
        MovimientoProveedorId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        TerceroId bigint NOT NULL,
        DocumentoPorPagarId bigint NOT NULL,
        TipoMovimiento varchar(20) NOT NULL,
        FechaMovimiento date NOT NULL,
        FechaVencimiento date NULL,
        NumeroDocumento nvarchar(50) NOT NULL,
        Moneda char(3) NOT NULL,
        Cargo decimal(20,4) NOT NULL CONSTRAINT DF_MovimientoProveedor_Cargo DEFAULT 0,
        Abono decimal(20,4) NOT NULL CONSTRAINT DF_MovimientoProveedor_Abono DEFAULT 0,
        TipoDocumentoOrigen varchar(40) NOT NULL,
        DocumentoOrigenId bigint NOT NULL,
        CreadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_MovimientoProveedor_Creado DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_MovimientoProveedor PRIMARY KEY CLUSTERED(MovimientoProveedorId),
        CONSTRAINT UQ_MovimientoProveedor_Origen UNIQUE(EmpresaId,TipoDocumentoOrigen,DocumentoOrigenId,TipoMovimiento),
        CONSTRAINT FK_MovimientoProveedor_Empresa FOREIGN KEY(EmpresaId) REFERENCES core.Empresa(EmpresaId),
        CONSTRAINT FK_MovimientoProveedor_Tercero FOREIGN KEY(EmpresaId,TerceroId) REFERENCES ter.Tercero(EmpresaId,TerceroId),
        CONSTRAINT FK_MovimientoProveedor_Documento FOREIGN KEY(EmpresaId,DocumentoPorPagarId) REFERENCES cxp.DocumentoPorPagar(EmpresaId,DocumentoPorPagarId),
        CONSTRAINT CK_MovimientoProveedor_Tipo CHECK(TipoMovimiento IN('FACTURA','PAGO','NOTA_CREDITO','ANTICIPO','APLICACION','REVERSO')),
        CONSTRAINT CK_MovimientoProveedor_Valores CHECK((Cargo>0 AND Abono=0) OR (Abono>0 AND Cargo=0))
    );

    CREATE INDEX IX_MovimientoProveedor_EstadoCuenta
        ON cxp.MovimientoProveedor(EmpresaId,TerceroId,FechaMovimiento,MovimientoProveedorId)
        INCLUDE(NumeroDocumento,Cargo,Abono,Moneda,DocumentoPorPagarId);

    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cxp.DocumentoPorPagar;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cxp.DocumentoPorPagar AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cxp.DocumentoPorPagar AFTER UPDATE;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cxp.MovimientoProveedor;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cxp.MovimientoProveedor AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cxp.MovimientoProveedor AFTER UPDATE;');

    INSERT cxp.DocumentoPorPagar
    (
        EmpresaId,DocumentoProveedorId,TerceroId,FechaReconocimiento,FechaDocumento,FechaVencimiento,
        Moneda,ValorOriginal,SaldoPendiente,Estado,ReconocidoEnUtc
    )
    SELECT d.EmpresaId,d.DocumentoProveedorId,d.TerceroId,COALESCE(f.FechaContable,d.FechaDocumento),d.FechaDocumento,
           COALESCE(d.FechaVencimiento,d.FechaDocumento),d.Moneda,d.TotalPagar,d.TotalPagar,'ABIERTA',COALESCE(f.ContabilizadoEnUtc,d.CreadoEnUtc)
    FROM comp.DocumentoProveedor d
    OUTER APPLY
    (
        SELECT MAX(x.FechaContable) FechaContable,MAX(x.ContabilizadoEnUtc) ContabilizadoEnUtc
        FROM
        (
            SELECT r.FechaContable,r.ContabilizadoEnUtc FROM inv.RecepcionMercancia r
            WHERE r.EmpresaId=d.EmpresaId AND r.DocumentoProveedorId=d.DocumentoProveedorId AND r.Estado='CONTABILIZADA'
            UNION ALL
            SELECT c.FechaContable,c.ContabilizadoEnUtc FROM comp.CausacionServicio c
            WHERE c.EmpresaId=d.EmpresaId AND c.DocumentoProveedorId=d.DocumentoProveedorId AND c.Estado='CONTABILIZADA'
        ) x
    ) f
    WHERE d.Estado='CONTABILIZADO' AND d.TipoDocumento IN('FACTURA','DOCUMENTO_SOPORTE') AND d.TotalPagar>0;

    INSERT cxp.MovimientoProveedor
    (
        EmpresaId,TerceroId,DocumentoPorPagarId,TipoMovimiento,FechaMovimiento,FechaVencimiento,
        NumeroDocumento,Moneda,Cargo,Abono,TipoDocumentoOrigen,DocumentoOrigenId,CreadoEnUtc
    )
    SELECT p.EmpresaId,p.TerceroId,p.DocumentoPorPagarId,'FACTURA',p.FechaReconocimiento,p.FechaVencimiento,
           d.NumeroDocumento,p.Moneda,p.ValorOriginal,0,'DOCUMENTO_PROVEEDOR',p.DocumentoProveedorId,p.ReconocidoEnUtc
    FROM cxp.DocumentoPorPagar p
    JOIN comp.DocumentoProveedor d ON d.EmpresaId=p.EmpresaId AND d.DocumentoProveedorId=p.DocumentoProveedorId;

    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('043_supplier_accounts_payable',N'Cartera de proveedores generada al contabilizar completamente la compra');

    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO

CREATE OR ALTER TRIGGER cxp.tr_MovimientoProveedor_Inmutable
ON cxp.MovimientoProveedor
AFTER UPDATE,DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF COALESCE(TRY_CONVERT(bit,SESSION_CONTEXT(N'BypassRls')),0)<>1
        THROW 52100,'Los movimientos del estado de cuenta son inmutables; registra un movimiento compensatorio.',1;
END;
GO

CREATE OR ALTER TRIGGER comp.tr_DocumentoProveedor_Cartera
ON comp.DocumentoProveedor
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    INSERT cxp.DocumentoPorPagar
    (
        EmpresaId,DocumentoProveedorId,TerceroId,FechaReconocimiento,FechaDocumento,FechaVencimiento,
        Moneda,ValorOriginal,SaldoPendiente,Estado,ReconocidoEnUtc
    )
    SELECT i.EmpresaId,i.DocumentoProveedorId,i.TerceroId,COALESCE(f.FechaContable,i.FechaDocumento),i.FechaDocumento,
           COALESCE(i.FechaVencimiento,i.FechaDocumento),i.Moneda,i.TotalPagar,i.TotalPagar,'ABIERTA',SYSUTCDATETIME()
    FROM inserted i
    JOIN deleted d ON d.EmpresaId=i.EmpresaId AND d.DocumentoProveedorId=i.DocumentoProveedorId
    OUTER APPLY
    (
        SELECT MAX(x.FechaContable) FechaContable
        FROM
        (
            SELECT r.FechaContable FROM inv.RecepcionMercancia r
            WHERE r.EmpresaId=i.EmpresaId AND r.DocumentoProveedorId=i.DocumentoProveedorId AND r.Estado='CONTABILIZADA'
            UNION ALL
            SELECT c.FechaContable FROM comp.CausacionServicio c
            WHERE c.EmpresaId=i.EmpresaId AND c.DocumentoProveedorId=i.DocumentoProveedorId AND c.Estado='CONTABILIZADA'
        ) x
    ) f
    WHERE i.Estado='CONTABILIZADO' AND d.Estado<>'CONTABILIZADO'
      AND i.TipoDocumento IN('FACTURA','DOCUMENTO_SOPORTE') AND i.TotalPagar>0
      AND NOT EXISTS
      (
          SELECT 1 FROM cxp.DocumentoPorPagar p WITH(UPDLOCK,HOLDLOCK)
          WHERE p.EmpresaId=i.EmpresaId AND p.DocumentoProveedorId=i.DocumentoProveedorId
      );

    INSERT cxp.MovimientoProveedor
    (
        EmpresaId,TerceroId,DocumentoPorPagarId,TipoMovimiento,FechaMovimiento,FechaVencimiento,
        NumeroDocumento,Moneda,Cargo,Abono,TipoDocumentoOrigen,DocumentoOrigenId
    )
    SELECT p.EmpresaId,p.TerceroId,p.DocumentoPorPagarId,'FACTURA',p.FechaReconocimiento,p.FechaVencimiento,
           i.NumeroDocumento,p.Moneda,p.ValorOriginal,0,'DOCUMENTO_PROVEEDOR',p.DocumentoProveedorId
    FROM inserted i
    JOIN deleted d ON d.EmpresaId=i.EmpresaId AND d.DocumentoProveedorId=i.DocumentoProveedorId
    JOIN cxp.DocumentoPorPagar p ON p.EmpresaId=i.EmpresaId AND p.DocumentoProveedorId=i.DocumentoProveedorId
    WHERE i.Estado='CONTABILIZADO' AND d.Estado<>'CONTABILIZADO'
      AND NOT EXISTS
      (
          SELECT 1 FROM cxp.MovimientoProveedor m WITH(UPDLOCK,HOLDLOCK)
          WHERE m.EmpresaId=i.EmpresaId AND m.TipoDocumentoOrigen='DOCUMENTO_PROVEEDOR'
            AND m.DocumentoOrigenId=i.DocumentoProveedorId AND m.TipoMovimiento='FACTURA'
      );

    INSERT cxp.MovimientoProveedor
    (
        EmpresaId,TerceroId,DocumentoPorPagarId,TipoMovimiento,FechaMovimiento,FechaVencimiento,
        NumeroDocumento,Moneda,Cargo,Abono,TipoDocumentoOrigen,DocumentoOrigenId
    )
    SELECT p.EmpresaId,p.TerceroId,p.DocumentoPorPagarId,'REVERSO',CONVERT(date,SYSUTCDATETIME()),p.FechaVencimiento,
           CONCAT(N'REV-',i.NumeroDocumento),p.Moneda,0,p.SaldoPendiente,'DOCUMENTO_PROVEEDOR',p.DocumentoProveedorId
    FROM inserted i
    JOIN deleted d ON d.EmpresaId=i.EmpresaId AND d.DocumentoProveedorId=i.DocumentoProveedorId
    JOIN cxp.DocumentoPorPagar p ON p.EmpresaId=i.EmpresaId AND p.DocumentoProveedorId=i.DocumentoProveedorId
    WHERE d.Estado='CONTABILIZADO' AND i.Estado='REVERTIDO' AND p.SaldoPendiente>0
      AND NOT EXISTS
      (
          SELECT 1 FROM cxp.MovimientoProveedor m WITH(UPDLOCK,HOLDLOCK)
          WHERE m.EmpresaId=i.EmpresaId AND m.TipoDocumentoOrigen='DOCUMENTO_PROVEEDOR'
            AND m.DocumentoOrigenId=i.DocumentoProveedorId AND m.TipoMovimiento='REVERSO'
      );

    UPDATE p SET SaldoPendiente=0,Estado='ANULADA',ActualizadoEnUtc=SYSUTCDATETIME()
    FROM cxp.DocumentoPorPagar p
    JOIN inserted i ON i.EmpresaId=p.EmpresaId AND i.DocumentoProveedorId=p.DocumentoProveedorId
    JOIN deleted d ON d.EmpresaId=i.EmpresaId AND d.DocumentoProveedorId=i.DocumentoProveedorId
    WHERE d.Estado='CONTABILIZADO' AND i.Estado='REVERTIDO';
END;
GO
