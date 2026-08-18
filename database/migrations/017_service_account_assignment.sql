SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='017_service_account_assignment')
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('017_service_account_assignment',N'Asignación validada de cuentas y dimensiones a servicios');
GO

CREATE OR ALTER PROCEDURE comp.usp_AsignarCuentasCausacion
    @EmpresaId bigint,@CausacionServicioId bigint,@CentroCostoCodigo nvarchar(50)=NULL,@ProyectoCodigo nvarchar(50)=NULL,@LineasJson nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF ISJSON(@LineasJson)<>1 THROW 51896,'Las asignaciones deben enviarse como JSON válido.',1;
    BEGIN TRANSACTION;
    DECLARE @Estado varchar(15);
    SELECT @Estado=Estado FROM comp.CausacionServicio WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND CausacionServicioId=@CausacionServicioId;
    IF @Estado IS NULL THROW 51897,'La causación no existe o no pertenece a la empresa.',1;
    IF @Estado NOT IN('BORRADOR','VALIDADA') THROW 51898,'La causación ya no admite cambios contables.',1;
    IF (SELECT COUNT(*) FROM OPENJSON(@LineasJson))<>(SELECT COUNT(*) FROM comp.CausacionServicioLinea WHERE EmpresaId=@EmpresaId AND CausacionServicioId=@CausacionServicioId)
        THROW 51899,'Debe asignarse una cuenta a cada línea de servicio.',1;
    IF EXISTS
    (
        SELECT 1 FROM OPENJSON(@LineasJson) WITH(NumeroLinea int '$.numeroLinea',CuentaContableCodigo nvarchar(30) '$.cuentaContableCodigo') j
        LEFT JOIN cont.CuentaContable c ON c.EmpresaId=@EmpresaId AND c.Codigo=j.CuentaContableCodigo AND c.Activa=1 AND c.PermiteMovimiento=1
        WHERE c.CuentaContableId IS NULL OR c.Tipo NOT IN('GASTO','COSTO','ACTIVO')
    ) THROW 51900,'Una cuenta asignada no existe, está inactiva o no es válida para el servicio.',1;
    UPDATE l SET CuentaContableCodigo=j.CuentaContableCodigo
    FROM comp.CausacionServicioLinea l
    JOIN OPENJSON(@LineasJson) WITH(NumeroLinea int '$.numeroLinea',CuentaContableCodigo nvarchar(30) '$.cuentaContableCodigo') j ON j.NumeroLinea=l.NumeroLinea
    WHERE l.EmpresaId=@EmpresaId AND l.CausacionServicioId=@CausacionServicioId;
    IF @@ROWCOUNT<>(SELECT COUNT(*) FROM comp.CausacionServicioLinea WHERE EmpresaId=@EmpresaId AND CausacionServicioId=@CausacionServicioId)
        THROW 51901,'Una asignación no corresponde a las líneas de la causación.',1;
    UPDATE comp.CausacionServicio SET CentroCostoCodigo=NULLIF(LTRIM(RTRIM(@CentroCostoCodigo)),N''),ProyectoCodigo=NULLIF(LTRIM(RTRIM(@ProyectoCodigo)),N''),Estado='VALIDADA'
    WHERE EmpresaId=@EmpresaId AND CausacionServicioId=@CausacionServicioId;
    COMMIT;
    SELECT @CausacionServicioId CausacionServicioId,CAST('VALIDADA' AS varchar(15)) Estado;
END;
GO
