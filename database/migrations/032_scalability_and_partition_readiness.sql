SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='032_scalability_and_partition_readiness')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;

    ALTER TABLE inv.MovimientoInventario ADD PeriodoParticion AS (DATEPART(year,FechaContable)*100+DATEPART(month,FechaContable)) PERSISTED;
    CREATE INDEX IX_MovimientoInventario_Historico ON inv.MovimientoInventario(EmpresaId,FechaContable,ArticuloId,BodegaId,MovimientoInventarioId)
        INCLUDE(CantidadEntrada,CantidadSalida,ValorMovimiento,CostoUnitarioMovimiento,ExistenciaPosterior,ValorTotalPosterior,TipoMovimiento);
    CREATE INDEX IX_MovimientoInventario_Particion ON inv.MovimientoInventario(PeriodoParticion,EmpresaId,MovimientoInventarioId)
        INCLUDE(FechaContable,BodegaId,ArticuloId,ValorMovimiento);
    CREATE INDEX IX_MovimientoInventario_Relacionado ON inv.MovimientoInventario(EmpresaId,MovimientoRelacionadoId)
        INCLUDE(TipoDocumentoOrigen,DocumentoOrigenId,CantidadEntrada,CantidadSalida) WHERE MovimientoRelacionadoId IS NOT NULL;
    CREATE INDEX IX_SaldoOrigen_Origen ON inv.SaldoOrigenBodega(EmpresaId,OrigenInventarioId,BodegaId,ArticuloId)
        INCLUDE(CantidadDisponible);
    CREATE INDEX IX_DocumentoProveedor_Cufe ON comp.DocumentoProveedor(EmpresaId,CufeCude) WHERE CufeCude IS NOT NULL;
    CREATE INDEX IX_DocumentoProveedor_HashXml ON comp.DocumentoProveedor(EmpresaId,HashXml) WHERE HashXml IS NOT NULL;

    CREATE TABLE core.PoliticaParticionKardex
    (
        EmpresaId bigint NOT NULL,
        Granularidad varchar(15) NOT NULL CONSTRAINT DF_PoliticaParticion_Granularidad DEFAULT 'MENSUAL',
        MesesEnLinea int NOT NULL CONSTRAINT DF_PoliticaParticion_Meses DEFAULT 36,
        ComprimirParticionesCerradas bit NOT NULL CONSTRAINT DF_PoliticaParticion_Comprimir DEFAULT 1,
        ArchivadoHabilitado bit NOT NULL CONSTRAINT DF_PoliticaParticion_Archivado DEFAULT 0,
        UltimaEvaluacionEnUtc datetime2(7) NULL,
        CONSTRAINT PK_PoliticaParticionKardex PRIMARY KEY CLUSTERED(EmpresaId),
        CONSTRAINT FK_PoliticaParticionKardex_Empresa FOREIGN KEY(EmpresaId) REFERENCES core.Empresa(EmpresaId),
        CONSTRAINT CK_PoliticaParticionKardex_Granularidad CHECK(Granularidad IN('MENSUAL','TRIMESTRAL','ANUAL')),
        CONSTRAINT CK_PoliticaParticionKardex_Meses CHECK(MesesEnLinea BETWEEN 12 AND 240)
    );
    INSERT core.PoliticaParticionKardex(EmpresaId) SELECT EmpresaId FROM core.Empresa;
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.PoliticaParticionKardex;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.PoliticaParticionKardex AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.PoliticaParticionKardex AFTER UPDATE;');

    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('032_scalability_and_partition_readiness',N'Indices de escala, clave mensual y politica de particionamiento y archivo de Kardex');
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO

CREATE OR ALTER TRIGGER core.TR_Empresa_PoliticaParticion ON core.Empresa AFTER INSERT AS
BEGIN
    SET NOCOUNT ON;
    INSERT core.PoliticaParticionKardex(EmpresaId)
    SELECT EmpresaId FROM inserted i WHERE NOT EXISTS(SELECT 1 FROM core.PoliticaParticionKardex p WHERE p.EmpresaId=i.EmpresaId);
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_DiagnosticarCapacidadInventario @EmpresaId bigint
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @EmpresaId EmpresaId,
        (SELECT COUNT_BIG(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId) MovimientosKardex,
        (SELECT COUNT_BIG(*) FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId) SaldosMaterializados,
        (SELECT COUNT_BIG(*) FROM inv.UnidadSerializada WHERE EmpresaId=@EmpresaId) UnidadesSerializadas,
        (SELECT MIN(FechaContable) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId) PrimeraFecha,
        (SELECT MAX(FechaContable) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId) UltimaFecha,
        p.Granularidad,p.MesesEnLinea,p.ComprimirParticionesCerradas,p.ArchivadoHabilitado
    FROM core.PoliticaParticionKardex p WHERE p.EmpresaId=@EmpresaId;
END;
GO
