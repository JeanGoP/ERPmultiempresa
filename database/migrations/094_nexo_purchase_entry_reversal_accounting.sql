SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
CREATE OR ALTER VIEW cont.vw_AsientoNexo AS
WITH Documentos AS (
    SELECT e.EmpresaId,CAST('ENTRADA' AS varchar(30)) Tipo,CONVERT(bigint,r.RecepcionMercanciaId) OrigenId,
        r.FechaContable Fecha,CONVERT(varchar(2),e.Fuente) Fuente,CONVERT(varchar(30),e.Documento) Documento,
        r.TerceroId,d.NumeroDocumento Referencia,e.Snapshot
    FROM core.ZeusEnvio e JOIN inv.RecepcionMercancia r ON r.EmpresaId=e.EmpresaId AND r.RecepcionMercanciaId=e.RecepcionMercanciaId
    LEFT JOIN comp.DocumentoProveedor d ON d.EmpresaId=r.EmpresaId AND d.DocumentoProveedorId=r.DocumentoProveedorId
    WHERE e.Estado='CONTABILIZADO' AND e.Snapshot IS NOT NULL
        AND NOT EXISTS (
            SELECT 1 FROM inv.ReversionEntradaMercancia reversa
            WHERE reversa.EmpresaId=r.EmpresaId AND reversa.RecepcionMercanciaId=r.RecepcionMercanciaId
                AND reversa.ComprobanteOriginalId IS NOT NULL AND reversa.ComprobanteReversionId IS NOT NULL
        )
    UNION ALL
    SELECT reversa.EmpresaId,'REVERSO_ENTRADA',CONVERT(bigint,reversa.ReversionEntradaMercanciaId),reversa.FechaContable,
        reversa.ZeusFuente,reversa.ZeusDocumento,r.TerceroId,CONCAT('Reverso ',d.NumeroDocumento),reversa.ZeusSnapshot
    FROM inv.ReversionEntradaMercancia reversa
    JOIN inv.RecepcionMercancia r ON r.EmpresaId=reversa.EmpresaId AND r.RecepcionMercanciaId=reversa.RecepcionMercanciaId
    JOIN comp.DocumentoProveedor d ON d.EmpresaId=reversa.EmpresaId AND d.DocumentoProveedorId=reversa.DocumentoProveedorId
    WHERE reversa.Estado='CONTABILIZADA' AND reversa.ZeusEstado='CONTABILIZADO' AND reversa.ZeusSnapshot IS NOT NULL
        AND reversa.ComprobanteReversionId IS NULL
    UNION ALL
    SELECT e.EmpresaId,'EGRESO',CONVERT(bigint,e.EgresoId),e.FechaContable,e.ZeusFuente,e.ZeusDocumento,
        e.TerceroId,CONCAT('CE-',e.EgresoId),e.Snapshot
    FROM cxp.Egreso e WHERE e.ZeusEstado='CONTABILIZADO'
    UNION ALL
    SELECT f.EmpresaId,'FACTURA_VENTA',CONVERT(bigint,f.FacturaVentaId),f.FechaContable,f.ZeusFuente,f.ZeusDocumento,
        f.ClienteId,f.Numero,f.Snapshot
    FROM ven.FacturaVenta f WHERE f.ZeusEstado='CONTABILIZADO' AND f.Snapshot IS NOT NULL
    UNION ALL
    SELECT r.EmpresaId,'RECIBO_CAJA',CONVERT(bigint,r.ReciboCajaId),r.FechaContable,r.ZeusFuente,r.ZeusDocumento,
        r.ClienteId,CONCAT('RC-',r.ReciboCajaId),r.Snapshot
    FROM cxc.ReciboCaja r WHERE r.ZeusEstado='CONTABILIZADO' AND r.Snapshot IS NOT NULL
    UNION ALL
    SELECT r.EmpresaId,'REVERSO_RECIBO',CONVERT(bigint,r.ReciboCajaId),r.ReversionFecha,r.ReversionFuente,r.ReversionDocumento,
        r.ClienteId,CONCAT('Reverso RC-',r.ReciboCajaId),r.ReversionSnapshot
    FROM cxc.ReciboCaja r WHERE r.ReversionEstado='CONTABILIZADO' AND r.ReversionSnapshot IS NOT NULL
    UNION ALL
    SELECT n.EmpresaId,'NOTA_CARTERA',CONVERT(bigint,n.RefinanciacionCarteraId),n.FechaContable,n.ZeusFuente,n.ZeusDocumento,
        f.ClienteId,CONCAT('NC-',n.RefinanciacionCarteraId),n.Snapshot
    FROM ven.RefinanciacionCartera n JOIN ven.FacturaVenta f ON f.EmpresaId=n.EmpresaId AND f.FacturaVentaId=n.FacturaVentaId
    WHERE n.ZeusEstado='CONTABILIZADO'
), ZeusLineas AS (
    SELECT d.EmpresaId,d.Tipo,d.OrigenId,d.Fecha,d.Fuente,d.Documento,d.TerceroId,d.Referencia,
        TRY_CONVERT(int,j.[key])+1 NumeroLinea,
        CONVERT(varchar(30),JSON_VALUE(j.value,'$.Regla.Cuenta')) Cuenta,
        CONVERT(nvarchar(200),JSON_VALUE(j.value,'$.Regla.Concepto')) Descripcion,
        CONVERT(varchar(50),JSON_VALUE(j.value,'$.Regla.CentroCosto')) CentroCosto,
        CONVERT(decimal(20,4),CASE WHEN v.Valor>0 THEN v.Valor ELSE 0 END) Debito,
        CONVERT(decimal(20,4),CASE WHEN v.Valor<0 THEN -v.Valor ELSE 0 END) Credito
    FROM Documentos d CROSS APPLY OPENJSON(d.Snapshot,'$.Movimientos') j
    CROSS APPLY (SELECT TRY_CONVERT(decimal(20,4),JSON_VALUE(j.value,'$.Valor')) Valor) v
    WHERE v.Valor<>0 AND JSON_VALUE(j.value,'$.Regla.Cuenta') IS NOT NULL
)
SELECT EmpresaId,Tipo,OrigenId,Fecha,Fuente,Documento,TerceroId,Referencia,NumeroLinea,Cuenta,Descripcion,CentroCosto,Debito,Credito
FROM ZeusLineas
UNION ALL
SELECT c.EmpresaId,CONVERT(varchar(30),'COMPROBANTE_NEXO'),CONVERT(bigint,c.ComprobanteContableId),c.FechaContable,
    CONVERT(varchar(2),NULL),CONVERT(varchar(30),c.Numero),COALESCE(l.TerceroId,c.TerceroId),c.Concepto,
    l.NumeroLinea,CONVERT(varchar(30),a.Codigo),CONVERT(nvarchar(200),l.Descripcion),CONVERT(varchar(50),l.CentroCostoCodigo),l.Debito,l.Credito
FROM cont.ComprobanteContable c JOIN cont.ComprobanteContableLinea l ON l.EmpresaId=c.EmpresaId AND l.ComprobanteContableId=c.ComprobanteContableId
JOIN cont.CuentaContable a ON a.EmpresaId=l.EmpresaId AND a.CuentaContableId=l.CuentaContableId
WHERE c.Estado='CONTABILIZADO';
GO
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='094_nexo_purchase_entry_reversal_accounting')
    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('094_nexo_purchase_entry_reversal_accounting',N'Asientos confirmados de reversión de entradas sin duplicar los comprobantes locales');
COMMIT;
GO
