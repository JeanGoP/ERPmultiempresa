# Integration checks use the private connection and roll back every write.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$line=Get-Content -LiteralPath (Join-Path $root '.env') | Where-Object {$_ -match '^\s*ConnectionStrings__NexoErp\s*='} | Select-Object -First 1
if(-not $line){throw 'Falta conexion privada.'}
$connection=New-Object System.Data.SqlClient.SqlConnection (($line -split '=',2)[1].Trim().Trim('"').Trim("'"))
function Run([string]$sql){$cmd=$connection.CreateCommand();$cmd.CommandTimeout=30;$cmd.CommandText=$sql;[void]$cmd.ExecuteNonQuery()}
function Check([string]$name,[string]$sql,[int]$expected=0){
 try {
  Run 'BEGIN TRANSACTION;'
  try {Run $sql;if($expected){throw "Falto error esperado $expected"}}
  catch {if(-not $expected -or $_.Exception.InnerException.Number -ne $expected){throw}}
  Write-Output "OK: $name"
 } finally {Run 'IF @@TRANCOUNT>0 ROLLBACK;'}
}
try {
 $connection.Open()
 Write-Output ('Destino: '+$connection.DataSource+' / '+$connection.Database)
 $setup="DECLARE @E bigint=(SELECT MIN(EmpresaId) FROM core.Empresa WHERE Activa=1); EXEC sys.sp_set_session_context @key=N'EmpresaId',@value=@E;"
 $month="IF EXISTS(SELECT 1 FROM core.PeriodoInventario WHERE EmpresaId=@E AND FechaInicio<='2099-02-28' AND FechaFin>='2099-02-01') THROW 51999,'Mes de pruebas ocupado; no se modifica.',1; EXEC core.usp_AbrirPeriodoInventario @EmpresaId=@E,@Mes='2099-02-15',@UsuarioId=NULL;"
 Check 'Apertura mensual, limites e idempotencia' ($setup+$month+"
 EXEC core.usp_AbrirPeriodoInventario @EmpresaId=@E,@Mes='2099-02-01',@UsuarioId=NULL;
 IF (SELECT COUNT(*) FROM core.PeriodoInventario WHERE EmpresaId=@E AND Codigo='2099-02' AND FechaInicio='2099-02-01' AND FechaFin='2099-02-28' AND Estado='ABIERTO')<>1 THROW 51999,'Periodo incorrecto.',1;
 IF NOT EXISTS(SELECT 1 FROM audit.Evento WHERE EmpresaId=@E AND Operacion='ABRIR_PERIODO' AND DocumentoNumero='2099-02') THROW 51999,'Falta auditoria.',1;")
 Check 'Abrir no reabre meses cerrados' ($setup+$month+"UPDATE core.PeriodoInventario SET Estado='CERRADO' WHERE EmpresaId=@E AND Codigo='2099-02'; EXEC core.usp_AbrirPeriodoInventario @EmpresaId=@E,@Mes='2099-02-01',@UsuarioId=NULL;") 51582
 Check 'Preparacion rechaza fecha sin periodo abierto' ($setup+"
 DECLARE @D bigint=(SELECT TOP(1) d.DocumentoProveedorId FROM comp.DocumentoProveedor d WHERE d.EmpresaId=@E AND d.Estado IN('BORRADOR','VALIDADO') AND EXISTS(SELECT 1 FROM comp.DocumentoProveedorLinea l WHERE l.EmpresaId=@E AND l.DocumentoProveedorId=d.DocumentoProveedorId AND l.Clasificacion='INVENTARIO'));
 IF @D IS NULL THROW 51999,'No hay borrador para esta prueba.',1;
 EXEC comp.usp_PrepararProcesosDocumento @EmpresaId=@E,@DocumentoProveedorId=@D,@FechaContable='2099-02-01';") 51325
 Check 'Fallo posterior revierte fecha y periodo del borrador' ($setup+$month+"
 DECLARE @R bigint=(SELECT TOP(1) r.RecepcionMercanciaId FROM inv.RecepcionMercancia r WHERE r.EmpresaId=@E AND r.Estado IN('BORRADOR','VALIDADA') AND EXISTS(SELECT 1 FROM inv.RecepcionMercanciaLinea l WHERE l.EmpresaId=@E AND l.RecepcionMercanciaId=r.RecepcionMercanciaId));
 IF @R IS NULL THROW 51999,'No hay recepcion para esta prueba.',1;
 EXEC inv.usp_ContabilizarRecepcion @EmpresaId=@E,@RecepcionMercanciaId=@R,@FechaContableSolicitada='2099-02-01',@BodegasJson=N'[]';") 51506
 Check 'Reintento de contabilizada no altera su fecha' ($setup+"
 DECLARE @R bigint,@F date;SELECT TOP(1) @R=RecepcionMercanciaId,@F=FechaContable FROM inv.RecepcionMercancia WHERE EmpresaId=@E AND Estado='CONTABILIZADA';
 IF @R IS NULL THROW 51999,'No hay contabilizada para esta prueba.',1;
 EXEC inv.usp_ContabilizarRecepcion @EmpresaId=@E,@RecepcionMercanciaId=@R,@FechaContableSolicitada='2099-02-01';
 IF EXISTS(SELECT 1 FROM inv.RecepcionMercancia WHERE EmpresaId=@E AND RecepcionMercanciaId=@R AND FechaContable<>@F) THROW 51999,'Cambio una fecha contabilizada.',1;")
 Write-Output 'Pruebas terminadas. Todas las escrituras fueron revertidas; no se abrieron meses operativos ni se contabilizaron entradas.'
} finally {$connection.Dispose()}
