param(
    [string]$Instance = '(localdb)\MSSQLLocalDB',
    [int]$Workers = 8,
    [int]$OperationsPerWorker = 15
)

$ErrorActionPreference = 'Stop'
$databaseName = "NexoErpConcurrency_$PID"
$initScript = Join-Path $PSScriptRoot 'init-localdb.ps1'
$safeDatabaseName = $databaseName.Replace(']', ']]')

try {
    & $initScript -DatabaseName $databaseName -Instance $Instance
    if ($LASTEXITCODE -ne 0) { throw 'No fue posible preparar la base temporal de concurrencia.' }

    $setupSql = @"
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
DECLARE @EmpresaId bigint,@UnidadId bigint,@ArticuloId bigint,@BodegaId bigint;
INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES('CONC','900999001',N'QA Concurrencia'); SET @EmpresaId=SCOPE_IDENTITY();
INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);
INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES(@EmpresaId,'UND',N'Unidad','und'); SET @UnidadId=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId) VALUES(@EmpresaId,'ART',N'Articulo concurrente','INVENTARIO',1,@UnidadId); SET @ArticuloId=SCOPE_IDENTITY();
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'BOD',N'Bodega'); SET @BodegaId=SCOPE_IDENTITY();
INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-08','2026-08-01','2026-08-31');
"@
    & sqlcmd -S $Instance -E -b -d $databaseName -Q $setupSql
    if ($LASTEXITCODE -ne 0) { throw 'No fue posible crear el escenario concurrente.' }

    $jobs = for ($worker = 1; $worker -le $Workers; $worker++) {
        $workerNumber = $worker
        Start-Job -ScriptBlock {
            param($sqlInstance,$dbName,$workerId,$operationCount)
            $cost = 100 + $workerId
            $sql = @"
SET NOCOUNT ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
DECLARE @EmpresaId bigint=(SELECT EmpresaId FROM core.Empresa WHERE Codigo='CONC');
DECLARE @UnidadId bigint=(SELECT UnidadMedidaId FROM inv.UnidadMedida WHERE EmpresaId=@EmpresaId AND Codigo='UND');
DECLARE @ArticuloId bigint=(SELECT ArticuloId FROM inv.Articulo WHERE EmpresaId=@EmpresaId AND Codigo='ART');
DECLARE @BodegaId bigint=(SELECT BodegaId FROM inv.Bodega WHERE EmpresaId=@EmpresaId AND Codigo='BOD');
DECLARE @PeriodoId bigint=(SELECT PeriodoInventarioId FROM core.PeriodoInventario WHERE EmpresaId=@EmpresaId AND Codigo='2026-08');
DECLARE @i int=1;
WHILE @i<=$operationCount
BEGIN
    DECLARE @Key uniqueidentifier=NEWID();
    EXEC inv.usp_ContabilizarEntrada @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoId,
        @FechaMovimiento='2026-08-15',@FechaContable='2026-08-15',@TipoMovimiento='QA_CONCURRENCIA',@ModuloOrigen='QA',
        @TipoDocumentoOrigen='QA_CONCURRENCIA',@DocumentoOrigenId=$workerId,@DocumentoLineaOrigenId=@i,@NumeroDocumento=N'QA-CONC',
        @CantidadEntrada=1,@CostoUnitarioEntrada=$cost,@IdempotencyKey=@Key;
    SET @i+=1;
END;
"@
            $null = & sqlcmd -S $sqlInstance -E -b -d $dbName -Q $sql
            if ($LASTEXITCODE -ne 0) { throw "Fallo el trabajador concurrente $workerId." }
        } -ArgumentList $Instance,$databaseName,$workerNumber,$OperationsPerWorker
    }
    $jobs | Wait-Job | Out-Null
    $jobErrors = $jobs | Where-Object { $_.State -ne 'Completed' }
    if ($jobErrors) {
        $details = ($jobs | Receive-Job -ErrorAction SilentlyContinue | Out-String)
        throw "Una operacion concurrente fallo. $details"
    }
    $jobs | Receive-Job | Out-Null
    $jobs | Remove-Job -Force

    $expectedQuantity = $Workers * $OperationsPerWorker
    $sumWorkerCosts = 100 * $Workers + (($Workers * ($Workers + 1)) / 2)
    $expectedValue = $OperationsPerWorker * $sumWorkerCosts
    $validateSql = @"
SET NOCOUNT ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
DECLARE @EmpresaId bigint=(SELECT EmpresaId FROM core.Empresa WHERE Codigo='CONC');
DECLARE @ArticuloId bigint=(SELECT ArticuloId FROM inv.Articulo WHERE EmpresaId=@EmpresaId AND Codigo='ART');
DECLARE @BodegaId bigint=(SELECT BodegaId FROM inv.Bodega WHERE EmpresaId=@EmpresaId AND Codigo='BOD');
IF NOT EXISTS(SELECT 1 FROM inv.SaldoArticuloBodega WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId AND BodegaId=@BodegaId AND Existencia=$expectedQuantity AND ValorTotal=$expectedValue)
    THROW 51990,'El saldo concurrente perdio cantidad o valor.',1;
IF (SELECT COUNT(*) FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId)<>$expectedQuantity
    THROW 51991,'El Kardex concurrente perdio o duplico movimientos.',1;
IF EXISTS
(
    SELECT 1 FROM
    (
        SELECT MovimientoInventarioId,ExistenciaAnterior,ExistenciaPosterior,
               LAG(ExistenciaPosterior) OVER(ORDER BY MovimientoInventarioId) ExistenciaPrevia
        FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId
    ) x WHERE ExistenciaPrevia IS NOT NULL AND ExistenciaAnterior<>ExistenciaPrevia
) THROW 51992,'La secuencia del Kardex concurrente contiene una carrera.',1;
PRINT 'QA concurrencia correcto: $expectedQuantity movimientos serializados sin perdida de cantidad, valor ni secuencia.';
"@
    & sqlcmd -S $Instance -E -b -d $databaseName -Q $validateSql
    if ($LASTEXITCODE -ne 0) { throw 'La validacion final de concurrencia fallo.' }
}
finally {
    Get-Job | Where-Object { $_.Name -like 'Job*' } | Remove-Job -Force -ErrorAction SilentlyContinue
    $dropSql = "IF DB_ID(N'$databaseName') IS NOT NULL BEGIN ALTER DATABASE [$safeDatabaseName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$safeDatabaseName]; END;"
    & sqlcmd -S $Instance -E -b -Q $dropSql | Out-Null
}
