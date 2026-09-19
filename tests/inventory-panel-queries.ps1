# Read-only regression check: executes the actual queries used to load the panel.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$line=Get-Content -LiteralPath (Join-Path $root '.env') | Where-Object {$_ -match '^\s*ConnectionStrings__NexoErp\s*='} | Select-Object -First 1
if(-not $line){throw 'Falta conexion privada.'}
$connection=New-Object System.Data.SqlClient.SqlConnection (($line -split '=',2)[1].Trim().Trim('"').Trim("'"))
$source=[IO.File]::ReadAllText((Join-Path $root 'backend/NexoERP.Api/AdvancedControls/AdvancedControlsRepository.cs'))
try {
 $connection.Open()
 Write-Output ('Destino: '+$connection.DataSource+' / '+$connection.Database)
 $command=$connection.CreateCommand();$command.CommandText='SELECT EmpresaId FROM core.Empresa WHERE Activa=1'
 $companies=New-Object System.Data.DataTable;$companies.Load($command.ExecuteReader())
 foreach($company in $companies.Rows){
  $companyId=[long]$company.EmpresaId
  $command.CommandText="EXEC sys.sp_set_session_context @key=N'EmpresaId',@value=$companyId;"
  [void]$command.ExecuteNonQuery()
  foreach($method in @('GetPeriodsAsync','GetReconciliationsAsync','GetReversibleMovementsAsync','GetAuditAsync')){
   $match=[regex]::Match($source,($method+'\([^\r\n]+?q.CommandText="([^"]+)"'))
   if(-not $match.Success){throw "No se encontro consulta de $method"}
   $query=$connection.CreateCommand();$query.CommandText=$match.Groups[1].Value
   [void]$query.Parameters.AddWithValue('@E',$companyId)
   $table=New-Object System.Data.DataTable
   try {$table.Load($query.ExecuteReader())} catch {throw "$method empresa ${companyId}: $($_.Exception.Message)"}
   Write-Output "OK: $method empresa $companyId ($($table.Rows.Count) filas)"
  }
 }
} finally {$connection.Dispose()}
