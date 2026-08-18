SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='026_inventory_reconciliation')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
    CREATE TABLE inv.ReconciliacionInventario
    (
        ReconciliacionInventarioId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        BodegaId bigint NULL,
        ArticuloId bigint NULL,
        Estado varchar(15) NOT NULL,
        Diferencias int NOT NULL,
        EjecutadoPorUsuarioId bigint NULL,
        IniciadaEnUtc datetime2(7) NOT NULL,
        FinalizadaEnUtc datetime2(7) NOT NULL,
        CONSTRAINT PK_ReconciliacionInventario PRIMARY KEY CLUSTERED(ReconciliacionInventarioId),
        CONSTRAINT UQ_ReconciliacionInventario_EmpresaId UNIQUE(EmpresaId,ReconciliacionInventarioId),
        CONSTRAINT FK_ReconciliacionInventario_Empresa FOREIGN KEY(EmpresaId) REFERENCES core.Empresa(EmpresaId),
        CONSTRAINT FK_ReconciliacionInventario_Bodega FOREIGN KEY(EmpresaId,BodegaId) REFERENCES inv.Bodega(EmpresaId,BodegaId),
        CONSTRAINT FK_ReconciliacionInventario_Articulo FOREIGN KEY(EmpresaId,ArticuloId) REFERENCES inv.Articulo(EmpresaId,ArticuloId),
        CONSTRAINT FK_ReconciliacionInventario_Usuario FOREIGN KEY(EjecutadoPorUsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_ReconciliacionInventario_Estado CHECK(Estado IN('CUADRADO','DIFERENCIAS'))
    );
    CREATE TABLE inv.ReconciliacionInventarioDetalle
    (
        ReconciliacionInventarioDetalleId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        ReconciliacionInventarioId bigint NOT NULL,
        TipoDiferencia varchar(25) NOT NULL,
        BodegaId bigint NOT NULL,
        ArticuloId bigint NOT NULL,
        UbicacionId bigint NULL,
        LoteId bigint NULL,
        CantidadEsperada decimal(20,6) NOT NULL,
        CantidadMaterializada decimal(20,6) NOT NULL,
        ValorEsperado decimal(20,4) NULL,
        ValorMaterializado decimal(20,4) NULL,
        CostoEsperado decimal(20,8) NULL,
        CostoMaterializado decimal(20,8) NULL,
        CONSTRAINT PK_ReconciliacionInventarioDetalle PRIMARY KEY CLUSTERED(ReconciliacionInventarioDetalleId),
        CONSTRAINT FK_ReconciliacionDetalle_Reconciliacion FOREIGN KEY(EmpresaId,ReconciliacionInventarioId) REFERENCES inv.ReconciliacionInventario(EmpresaId,ReconciliacionInventarioId),
        CONSTRAINT CK_ReconciliacionDetalle_Tipo CHECK(TipoDiferencia IN('SALDO_KARDEX','UBICACION','LOTE_UBICACION','ORIGEN'))
    );
    CREATE INDEX IX_ReconciliacionInventario_Fecha ON inv.ReconciliacionInventario(EmpresaId,FinalizadaEnUtc DESC) INCLUDE(Estado,Diferencias,BodegaId,ArticuloId);
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.ReconciliacionInventario;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.ReconciliacionInventario AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.ReconciliacionInventarioDetalle;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.ReconciliacionInventarioDetalle AFTER INSERT;');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('026_inventory_reconciliation',N'Reconciliación persistente entre Kardex, saldos, ubicaciones, lotes y orígenes');
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_ReconciliarInventario
    @EmpresaId bigint,@BodegaId bigint=NULL,@ArticuloId bigint=NULL,@UsuarioId bigint=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    BEGIN TRANSACTION;
    DECLARE @Inicio datetime2(7)=SYSUTCDATETIME(),@Id bigint;
    INSERT inv.ReconciliacionInventario(EmpresaId,BodegaId,ArticuloId,Estado,Diferencias,EjecutadoPorUsuarioId,IniciadaEnUtc,FinalizadaEnUtc)
    VALUES(@EmpresaId,@BodegaId,@ArticuloId,'CUADRADO',0,@UsuarioId,@Inicio,@Inicio);
    SET @Id=SCOPE_IDENTITY();

    ;WITH Ultimo AS
    (
        SELECT *,ROW_NUMBER() OVER(PARTITION BY EmpresaId,BodegaId,ArticuloId ORDER BY MovimientoInventarioId DESC) rn
        FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND (@BodegaId IS NULL OR BodegaId=@BodegaId) AND (@ArticuloId IS NULL OR ArticuloId=@ArticuloId)
    ), Comparacion AS
    (
        SELECT COALESCE(s.BodegaId,m.BodegaId) BodegaId,COALESCE(s.ArticuloId,m.ArticuloId) ArticuloId,
               COALESCE(m.ExistenciaPosterior,0) Esperada,COALESCE(s.Existencia,0) Materializada,
               COALESCE(m.ValorTotalPosterior,0) ValorEsperado,COALESCE(s.ValorTotal,0) ValorMaterializado,
               COALESCE(m.CostoPromedioPosterior,0) CostoEsperado,COALESCE(s.CostoPromedio,0) CostoMaterializado
        FROM inv.SaldoArticuloBodega s FULL JOIN (SELECT * FROM Ultimo WHERE rn=1) m ON m.EmpresaId=s.EmpresaId AND m.BodegaId=s.BodegaId AND m.ArticuloId=s.ArticuloId
        WHERE COALESCE(s.EmpresaId,m.EmpresaId)=@EmpresaId AND (@BodegaId IS NULL OR COALESCE(s.BodegaId,m.BodegaId)=@BodegaId) AND (@ArticuloId IS NULL OR COALESCE(s.ArticuloId,m.ArticuloId)=@ArticuloId)
    )
    INSERT inv.ReconciliacionInventarioDetalle(EmpresaId,ReconciliacionInventarioId,TipoDiferencia,BodegaId,ArticuloId,CantidadEsperada,CantidadMaterializada,ValorEsperado,ValorMaterializado,CostoEsperado,CostoMaterializado)
    SELECT @EmpresaId,@Id,'SALDO_KARDEX',BodegaId,ArticuloId,Esperada,Materializada,ValorEsperado,ValorMaterializado,CostoEsperado,CostoMaterializado FROM Comparacion
    WHERE Esperada<>Materializada OR ValorEsperado<>ValorMaterializado OR CostoEsperado<>CostoMaterializado;

    ;WITH Esperado AS
    (
        SELECT BodegaId,UbicacionId,ArticuloId,SUM(CantidadEntrada-CantidadSalida) Cantidad FROM inv.MovimientoInventario
        WHERE EmpresaId=@EmpresaId AND UbicacionId IS NOT NULL AND (@BodegaId IS NULL OR BodegaId=@BodegaId) AND (@ArticuloId IS NULL OR ArticuloId=@ArticuloId)
        GROUP BY BodegaId,UbicacionId,ArticuloId
    ), Comparacion AS
    (
        SELECT COALESCE(e.BodegaId,s.BodegaId) BodegaId,COALESCE(e.UbicacionId,s.UbicacionId) UbicacionId,COALESCE(e.ArticuloId,s.ArticuloId) ArticuloId,COALESCE(e.Cantidad,0) Esperada,COALESCE(s.Existencia,0) Materializada
        FROM Esperado e FULL JOIN inv.SaldoArticuloUbicacion s ON s.EmpresaId=@EmpresaId AND s.BodegaId=e.BodegaId AND s.UbicacionId=e.UbicacionId AND s.ArticuloId=e.ArticuloId
        WHERE (s.EmpresaId IS NULL OR s.EmpresaId=@EmpresaId) AND (@BodegaId IS NULL OR COALESCE(e.BodegaId,s.BodegaId)=@BodegaId) AND (@ArticuloId IS NULL OR COALESCE(e.ArticuloId,s.ArticuloId)=@ArticuloId)
    )
    INSERT inv.ReconciliacionInventarioDetalle(EmpresaId,ReconciliacionInventarioId,TipoDiferencia,BodegaId,ArticuloId,UbicacionId,CantidadEsperada,CantidadMaterializada)
    SELECT @EmpresaId,@Id,'UBICACION',BodegaId,ArticuloId,UbicacionId,Esperada,Materializada FROM Comparacion WHERE Esperada<>Materializada;

    ;WITH Esperado AS
    (
        SELECT BodegaId,UbicacionId,ArticuloId,LoteId,SUM(CantidadEntrada-CantidadSalida) Cantidad FROM inv.MovimientoInventario
        WHERE EmpresaId=@EmpresaId AND UbicacionId IS NOT NULL AND LoteId IS NOT NULL AND (@BodegaId IS NULL OR BodegaId=@BodegaId) AND (@ArticuloId IS NULL OR ArticuloId=@ArticuloId)
        GROUP BY BodegaId,UbicacionId,ArticuloId,LoteId
    ), Comparacion AS
    (
        SELECT COALESCE(e.BodegaId,s.BodegaId) BodegaId,COALESCE(e.UbicacionId,s.UbicacionId) UbicacionId,COALESCE(e.ArticuloId,s.ArticuloId) ArticuloId,COALESCE(e.LoteId,s.LoteId) LoteId,COALESCE(e.Cantidad,0) Esperada,COALESCE(s.Existencia,0) Materializada
        FROM Esperado e FULL JOIN inv.SaldoArticuloLoteUbicacion s ON s.EmpresaId=@EmpresaId AND s.BodegaId=e.BodegaId AND s.UbicacionId=e.UbicacionId AND s.ArticuloId=e.ArticuloId AND s.LoteId=e.LoteId
        WHERE (s.EmpresaId IS NULL OR s.EmpresaId=@EmpresaId) AND (@BodegaId IS NULL OR COALESCE(e.BodegaId,s.BodegaId)=@BodegaId) AND (@ArticuloId IS NULL OR COALESCE(e.ArticuloId,s.ArticuloId)=@ArticuloId)
    )
    INSERT inv.ReconciliacionInventarioDetalle(EmpresaId,ReconciliacionInventarioId,TipoDiferencia,BodegaId,ArticuloId,UbicacionId,LoteId,CantidadEsperada,CantidadMaterializada)
    SELECT @EmpresaId,@Id,'LOTE_UBICACION',BodegaId,ArticuloId,UbicacionId,LoteId,Esperada,Materializada FROM Comparacion WHERE Esperada<>Materializada;

    INSERT inv.ReconciliacionInventarioDetalle(EmpresaId,ReconciliacionInventarioId,TipoDiferencia,BodegaId,ArticuloId,CantidadEsperada,CantidadMaterializada)
    SELECT @EmpresaId,@Id,'ORIGEN',s.BodegaId,s.ArticuloId,s.Existencia,COALESCE(o.Cantidad,0)
    FROM inv.SaldoArticuloBodega s OUTER APPLY(SELECT SUM(CantidadDisponible) Cantidad FROM inv.SaldoOrigenBodega o WHERE o.EmpresaId=s.EmpresaId AND o.BodegaId=s.BodegaId AND o.ArticuloId=s.ArticuloId) o
    WHERE s.EmpresaId=@EmpresaId AND (@BodegaId IS NULL OR s.BodegaId=@BodegaId) AND (@ArticuloId IS NULL OR s.ArticuloId=@ArticuloId) AND s.Existencia<>COALESCE(o.Cantidad,0);

    DECLARE @Diferencias int=(SELECT COUNT(*) FROM inv.ReconciliacionInventarioDetalle WHERE EmpresaId=@EmpresaId AND ReconciliacionInventarioId=@Id);
    DECLARE @Estado varchar(15)=CASE WHEN @Diferencias=0 THEN 'CUADRADO' ELSE 'DIFERENCIAS' END;
    UPDATE inv.ReconciliacionInventario SET Estado=@Estado,Diferencias=@Diferencias,FinalizadaEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@EmpresaId AND ReconciliacionInventarioId=@Id;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
    VALUES(@EmpresaId,@UsuarioId,'INVENTARIO_RECONCILIADO','inv.ReconciliacionInventario',CONVERT(nvarchar(100),@Id),CONCAT(N'{"estado":"',@Estado,N'","diferencias":',@Diferencias,N'}'),'INVENTARIO');
    COMMIT;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    SELECT @Id ReconciliacionInventarioId,@Estado Estado,@Diferencias Diferencias;
END;
GO
