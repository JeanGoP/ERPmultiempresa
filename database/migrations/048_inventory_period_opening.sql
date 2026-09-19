SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
GO
CREATE OR ALTER PROCEDURE core.usp_AbrirPeriodoInventario
    @EmpresaId bigint,@Mes date,@UsuarioId bigint
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @Mes IS NULL THROW 51580,'Selecciona el mes que deseas abrir.',1;
    DECLARE @Inicio date=DATEFROMPARTS(YEAR(@Mes),MONTH(@Mes),1),@Fin date=EOMONTH(@Mes),@Id bigint,@Estado varchar(15),@Empresa bigint;
    DECLARE @Codigo char(7)=CONVERT(char(7),@Mes,126);
    BEGIN TRANSACTION;
    SELECT @Empresa=EmpresaId FROM core.Empresa WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND Activa=1;
    IF @Empresa IS NULL THROW 51581,'La empresa no existe o no esta activa.',1;
    SELECT @Id=PeriodoInventarioId,@Estado=Estado FROM core.PeriodoInventario WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND Codigo=@Codigo;
    IF @Id IS NOT NULL
    BEGIN
        IF @Estado NOT IN('ABIERTO','REABIERTO') THROW 51582,'El periodo ya existe y no esta abierto. Usa la reapertura autorizada con motivo.',1;
    END
    ELSE
    BEGIN
        IF EXISTS(SELECT 1 FROM core.PeriodoInventario WHERE EmpresaId=@EmpresaId AND FechaInicio<=@Fin AND FechaFin>=@Inicio)
            THROW 51583,'El mes se superpone con otro periodo existente.',1;
        INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin,Estado) VALUES(@EmpresaId,@Codigo,@Inicio,@Fin,'ABIERTO');
        SET @Id=SCOPE_IDENTITY();
        INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresPosteriores,AplicacionOrigen)
        VALUES(@EmpresaId,@UsuarioId,'ABRIR_PERIODO','core.PeriodoInventario',@Id,@Codigo,N'{"estado":"ABIERTO"}','ERP');
    END;
    COMMIT;
    SELECT PeriodoInventarioId,Codigo,FechaInicio,FechaFin,Estado FROM core.PeriodoInventario WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@Id;
END;
GO
DECLARE @Sql nvarchar(max)=OBJECT_DEFINITION(OBJECT_ID('comp.usp_PrepararProcesosDocumento'));
IF @Sql IS NULL THROW 51584,'No existe el procedimiento de preparacion.',1;
IF CHARINDEX('PERIODO_POR_FECHA_048',@Sql)=0
BEGIN
    DECLARE @Anchor nvarchar(200)=N'IF @BodegaId IS NULL OR @PeriodoInventarioId IS NULL';
    IF CHARINDEX(@Anchor,@Sql)=0 THROW 51584,'No se encontro el punto de validacion de preparacion.',1;
    SET @Sql=STUFF(@Sql,1,CHARINDEX('PROCEDURE',@Sql)-1,'ALTER ');
    SET @Sql=REPLACE(@Sql,@Anchor,N'-- PERIODO_POR_FECHA_048
        SET @PeriodoInventarioId=NULL;
        IF (SELECT COUNT(*) FROM core.PeriodoInventario WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND Estado IN(''ABIERTO'',''REABIERTO'') AND @FechaContable BETWEEN FechaInicio AND FechaFin)<>1
            THROW 51325,''No hay un unico periodo de inventario abierto para la fecha contable. Abre el mes en Periodos de inventario.'',1;
        SELECT @PeriodoInventarioId=PeriodoInventarioId FROM core.PeriodoInventario WHERE EmpresaId=@EmpresaId AND Estado IN(''ABIERTO'',''REABIERTO'') AND @FechaContable BETWEEN FechaInicio AND FechaFin;
        IF @BodegaId IS NULL OR @PeriodoInventarioId IS NULL');
    EXEC sys.sp_executesql @Sql;
END;
SET @Sql=OBJECT_DEFINITION(OBJECT_ID('inv.usp_ContabilizarRecepcion'));
IF @Sql IS NULL THROW 51584,'No existe el procedimiento de contabilizacion.',1;
IF CHARINDEX('@FechaContableSolicitada',@Sql)=0
BEGIN
    IF CHARINDEX('@BodegasJson nvarchar(max)=NULL',@Sql)=0 OR CHARINDEX('IF @Estado NOT IN',@Sql)=0
        THROW 51584,'No se encontro el punto de validacion de contabilizacion.',1;
    SET @Sql=STUFF(@Sql,1,CHARINDEX('PROCEDURE',@Sql)-1,'ALTER ');
    SET @Sql=REPLACE(@Sql,'@BodegasJson nvarchar(max)=NULL','@BodegasJson nvarchar(max)=NULL, @FechaContableSolicitada date=NULL');
    SET @Sql=REPLACE(@Sql,'IF @Estado NOT IN',N'
    IF @Estado IN(''BORRADOR'',''VALIDADA'')
    BEGIN
        SET @FechaContable=COALESCE(@FechaContableSolicitada,@FechaContable);
        IF (SELECT COUNT(*) FROM core.PeriodoInventario WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND Estado IN(''ABIERTO'',''REABIERTO'') AND @FechaContable BETWEEN FechaInicio AND FechaFin)<>1
            THROW 51503,''No hay un unico periodo de inventario abierto para la fecha contable. Abre el mes en Periodos de inventario.'',1;
        SELECT @PeriodoInventarioId=PeriodoInventarioId FROM core.PeriodoInventario WHERE EmpresaId=@EmpresaId AND Estado IN(''ABIERTO'',''REABIERTO'') AND @FechaContable BETWEEN FechaInicio AND FechaFin;
        UPDATE inv.RecepcionMercancia SET FechaContable=@FechaContable,PeriodoInventarioId=@PeriodoInventarioId
        WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionMercanciaId;
    END;
    IF @Estado NOT IN');
    EXEC sys.sp_executesql @Sql;
END;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='048_inventory_period_opening')
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('048_inventory_period_opening',N'Apertura mensual y periodo automatico por fecha contable de recepcion');
COMMIT;
GO
