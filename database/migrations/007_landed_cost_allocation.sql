SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT 1 FROM core.SchemaMigration WHERE MigrationId='007_landed_cost_allocation')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;

    CREATE TABLE cost.DistribucionCostoObjetivo
    (
        DistribucionCostoObjetivoId bigint         IDENTITY(1,1) NOT NULL,
        EmpresaId                   bigint         NOT NULL,
        DistribucionCostoId         bigint         NOT NULL,
        RecepcionMercanciaLineaId   bigint         NOT NULL,
        BaseManual                  decimal(28,10) NULL,
        PorcentajeManual            decimal(12,8)  NULL,
        ValorManual                 decimal(20,4)  NULL,
        CONSTRAINT PK_DistribucionCostoObjetivo PRIMARY KEY CLUSTERED (DistribucionCostoObjetivoId),
        CONSTRAINT UQ_DistribucionCostoObjetivo UNIQUE(EmpresaId,DistribucionCostoId,RecepcionMercanciaLineaId),
        CONSTRAINT FK_DistribucionCostoObjetivo_Distribucion FOREIGN KEY(EmpresaId,DistribucionCostoId) REFERENCES cost.DistribucionCosto(EmpresaId,DistribucionCostoId),
        CONSTRAINT FK_DistribucionCostoObjetivo_Recepcion FOREIGN KEY(EmpresaId,RecepcionMercanciaLineaId) REFERENCES inv.RecepcionMercanciaLinea(EmpresaId,RecepcionMercanciaLineaId),
        CONSTRAINT CK_DistribucionCostoObjetivo_Valores CHECK((BaseManual IS NULL OR BaseManual>=0) AND (PorcentajeManual IS NULL OR PorcentajeManual BETWEEN 0 AND 100) AND (ValorManual IS NULL OR ValorManual>=0))
    );

    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cost.DistribucionCostoObjetivo;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cost.DistribucionCostoObjetivo AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cost.DistribucionCostoObjetivo AFTER UPDATE;');

    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('007_landed_cost_allocation',N'Objetivos y motor exacto de distribución de costos adicionales');
    COMMIT TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO

CREATE OR ALTER PROCEDURE cost.usp_CalcularDistribucionCosto
    @EmpresaId bigint,
    @DistribucionCostoId bigint,
    @UsuarioId bigint=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;

    DECLARE @Metodo varchar(25);
    DECLARE @ValorTotal decimal(20,4);
    DECLARE @Estado varchar(20);
    SELECT @Metodo=Metodo,@ValorTotal=ValorTotal,@Estado=Estado
    FROM cost.DistribucionCosto WITH(UPDLOCK,HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND DistribucionCostoId=@DistribucionCostoId;
    IF @Metodo IS NULL THROW 51400,'La distribución no existe.',1;
    IF @Estado NOT IN('CALCULADA') THROW 51401,'Solo una distribución calculada y no aplicada puede recalcularse.',1;
    IF NOT EXISTS(SELECT 1 FROM cost.DistribucionCostoObjetivo WHERE EmpresaId=@EmpresaId AND DistribucionCostoId=@DistribucionCostoId)
        THROW 51402,'La distribución no tiene líneas objetivo.',1;

    CREATE TABLE #Bases
    (
        Orden int NOT NULL,
        RecepcionMercanciaLineaId bigint NOT NULL PRIMARY KEY,
        Base decimal(28,10) NOT NULL,
        CantidadBase decimal(20,6) NOT NULL,
        CostoAntes decimal(20,8) NOT NULL
    );

    INSERT #Bases(Orden,RecepcionMercanciaLineaId,Base,CantidadBase,CostoAntes)
    SELECT
        ROW_NUMBER() OVER(ORDER BY o.RecepcionMercanciaLineaId),
        o.RecepcionMercanciaLineaId,
        CAST(CASE @Metodo
            WHEN 'VALOR_COMPRA' THEN r.CostoTotalCapitalizable
            WHEN 'CANTIDAD' THEN r.CantidadBase
            WHEN 'PESO' THEN r.CantidadBase*COALESCE(a.PesoBaseKg,0)
            WHEN 'VOLUMEN' THEN r.CantidadBase*COALESCE(a.VolumenBaseM3,0)
            WHEN 'VALOR_CANTIDAD' THEN r.CantidadBase*r.CostoUnitarioDocumento
            WHEN 'PORCENTAJE_MANUAL' THEN COALESCE(o.PorcentajeManual,0)
            WHEN 'VALOR_MANUAL' THEN COALESCE(o.ValorManual,0)
            WHEN 'COMBINADO' THEN COALESCE(o.BaseManual,0)
        END AS decimal(28,10)),
        r.CantidadBase,
        CAST(CASE WHEN r.CantidadBase=0 THEN 0 ELSE r.CostoTotalCapitalizable/r.CantidadBase END AS decimal(20,8))
    FROM cost.DistribucionCostoObjetivo o
    JOIN inv.RecepcionMercanciaLinea r ON r.EmpresaId=o.EmpresaId AND r.RecepcionMercanciaLineaId=o.RecepcionMercanciaLineaId
    JOIN inv.Articulo a ON a.EmpresaId=r.EmpresaId AND a.ArticuloId=r.ArticuloId
    WHERE o.EmpresaId=@EmpresaId AND o.DistribucionCostoId=@DistribucionCostoId;

    DECLARE @BaseTotal decimal(28,10)=(SELECT SUM(Base) FROM #Bases);
    IF @BaseTotal IS NULL OR @BaseTotal<=0 THROW 51403,'La base total de distribución debe ser mayor que cero.',1;
    IF @Metodo='PORCENTAJE_MANUAL' AND ABS(@BaseTotal-100)>0.000001 THROW 51404,'Los porcentajes manuales deben sumar exactamente 100.',1;
    IF @Metodo='VALOR_MANUAL' AND ABS(@BaseTotal-@ValorTotal)>0.0001 THROW 51405,'Los valores manuales deben sumar el total distribuible.',1;

    DELETE FROM cost.DistribucionCostoLinea WHERE EmpresaId=@EmpresaId AND DistribucionCostoId=@DistribucionCostoId;

    DECLARE @UltimoOrden int=(SELECT MAX(Orden) FROM #Bases);
    INSERT cost.DistribucionCostoLinea
    (
        EmpresaId,DistribucionCostoId,RecepcionMercanciaLineaId,BaseDistribucion,PorcentajeAsignado,
        ValorAsignado,CostoUnitarioAntes,CostoUnitarioDespues,EsLineaAjusteRedondeo
    )
    SELECT
        @EmpresaId,@DistribucionCostoId,RecepcionMercanciaLineaId,Base,
        CAST(Base*100/@BaseTotal AS decimal(12,8)),
        CAST(ROUND(CASE WHEN @Metodo='VALOR_MANUAL' THEN Base ELSE @ValorTotal*Base/@BaseTotal END,4) AS decimal(20,4)),
        CostoAntes,
        CAST(CostoAntes+(ROUND(CASE WHEN @Metodo='VALOR_MANUAL' THEN Base ELSE @ValorTotal*Base/@BaseTotal END,4)/CantidadBase) AS decimal(20,8)),
        0
    FROM #Bases;

    DECLARE @Diferencia decimal(20,4)=@ValorTotal-(SELECT SUM(ValorAsignado) FROM cost.DistribucionCostoLinea WHERE EmpresaId=@EmpresaId AND DistribucionCostoId=@DistribucionCostoId);
    IF @Diferencia<>0
    BEGIN
        UPDATE l
        SET ValorAsignado=ValorAsignado+@Diferencia,
            CostoUnitarioDespues=CAST(CostoUnitarioAntes+((ValorAsignado+@Diferencia)/b.CantidadBase) AS decimal(20,8)),
            EsLineaAjusteRedondeo=1
        FROM cost.DistribucionCostoLinea l
        JOIN #Bases b ON b.RecepcionMercanciaLineaId=l.RecepcionMercanciaLineaId
        WHERE l.EmpresaId=@EmpresaId AND l.DistribucionCostoId=@DistribucionCostoId AND b.Orden=@UltimoOrden;
    END;

    IF (SELECT SUM(ValorAsignado) FROM cost.DistribucionCostoLinea WHERE EmpresaId=@EmpresaId AND DistribucionCostoId=@DistribucionCostoId)<>@ValorTotal
        THROW 51406,'La distribución no reconcilia exactamente con el valor total.',1;

    UPDATE cost.DistribucionCosto
    SET BaseTotal=@BaseTotal,DiferenciaRedondeo=@Diferencia,CalculadaEnUtc=SYSUTCDATETIME(),CalculadaPorUsuarioId=@UsuarioId
    WHERE EmpresaId=@EmpresaId AND DistribucionCostoId=@DistribucionCostoId;

    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
    VALUES(@EmpresaId,@UsuarioId,'COSTO_DISTRIBUIDO','cost.DistribucionCosto',CONVERT(nvarchar(100),@DistribucionCostoId),
           CONCAT(N'{"metodo":"',@Metodo,N'","valor":',CONVERT(varchar(50),@ValorTotal),N',"base":',CONVERT(varchar(50),@BaseTotal),N',"redondeo":',CONVERT(varchar(50),@Diferencia),N'}'),'COSTOS');

    COMMIT TRANSACTION;
    SELECT l.RecepcionMercanciaLineaId,l.BaseDistribucion,l.PorcentajeAsignado,l.ValorAsignado,l.CostoUnitarioAntes,l.CostoUnitarioDespues,l.EsLineaAjusteRedondeo
    FROM cost.DistribucionCostoLinea l
    WHERE l.EmpresaId=@EmpresaId AND l.DistribucionCostoId=@DistribucionCostoId
    ORDER BY l.RecepcionMercanciaLineaId;
END;
GO
