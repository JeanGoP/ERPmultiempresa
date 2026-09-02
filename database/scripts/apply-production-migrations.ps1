param(
    [string]$HealthUrl = $env:ERP_API_HEALTH_URL
)

$ErrorActionPreference = 'Stop'
$connectionString = [Environment]::GetEnvironmentVariable('ConnectionStrings__NexoErp')
if ([string]::IsNullOrWhiteSpace($connectionString)) {
    throw 'Falta la variable ConnectionStrings__NexoErp con la conexión de la base desplegada.'
}

$builder = New-Object System.Data.Common.DbConnectionStringBuilder
$builder.set_ConnectionString($connectionString)
function Get-ConnectionValue([string[]]$Names) {
    foreach ($name in $Names) {
        if ($builder.ContainsKey($name)) { return [string]$builder[$name] }
    }
    return $null
}

$server = Get-ConnectionValue @('Server','Data Source','Address','Addr','Network Address')
$databaseName = Get-ConnectionValue @('Database','Initial Catalog')
$userName = Get-ConnectionValue @('User ID','UID')
$password = Get-ConnectionValue @('Password','Pwd')
$integratedSecurity = Get-ConnectionValue @('Integrated Security','Trusted_Connection')
$trustServerCertificate = Get-ConnectionValue @('TrustServerCertificate')

if ([string]::IsNullOrWhiteSpace($server) -or [string]::IsNullOrWhiteSpace($databaseName)) {
    throw 'La conexión desplegada debe indicar servidor y base de datos.'
}
if ($server -match '(?i)localdb' -or $databaseName -eq 'NexoErpDev') {
    throw 'Este comando es solo para la base desplegada y rechaza LocalDB/NexoErpDev.'
}

$usesIntegratedSecurity = $integratedSecurity -match '^(?i:true|yes|sspi)$'
if (-not $usesIntegratedSecurity -and ([string]::IsNullOrWhiteSpace($userName) -or [string]::IsNullOrWhiteSpace($password))) {
    throw 'La conexión SQL debe incluir usuario y contraseña o seguridad integrada.'
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$migrationFolder = Join-Path $projectRoot 'database\migrations'
$migrations = @(Get-ChildItem -LiteralPath $migrationFolder -Filter '*.sql' | Sort-Object Name)
if ($migrations.Count -eq 0) { throw 'No se encontraron migraciones para aplicar.' }
$latestMigration = [System.IO.Path]::GetFileNameWithoutExtension($migrations[-1].Name)

$sqlArgs = @('-S',$server,'-d',$databaseName,'-b')
if ($usesIntegratedSecurity) { $sqlArgs += '-E' } else { $sqlArgs += @('-U',$userName) }
if ($trustServerCertificate -match '^(?i:true|yes)$') { $sqlArgs += '-C' }

$previousSqlCmdPassword = $env:SQLCMDPASSWORD
try {
    if (-not $usesIntegratedSecurity) { $env:SQLCMDPASSWORD = $password }
    Write-Host "Aplicando $($migrations.Count) migraciones en la base desplegada $databaseName..."
    foreach ($migration in $migrations) {
        Write-Host "Aplicando $($migration.Name)..."
        & sqlcmd @sqlArgs -i $migration.FullName
        if ($LASTEXITCODE -ne 0) { throw "Falló la migración $($migration.Name)." }
    }

    $verificationQuery = "SET NOCOUNT ON; SELECT CONCAT(COUNT(*),'|',MAX(MigrationId)) FROM core.SchemaMigration;"
    $verification = (& sqlcmd @sqlArgs -h -1 -W -Q $verificationQuery | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1).Trim()
    $parts = $verification -split '\|',2
    if ($parts.Count -ne 2 -or [int]$parts[0] -lt $migrations.Count -or $parts[1] -ne $latestMigration) {
        throw "La base desplegada no confirmó todas las migraciones. Resultado: $verification"
    }
}
finally {
    $env:SQLCMDPASSWORD = $previousSqlCmdPassword
}

if ([string]::IsNullOrWhiteSpace($HealthUrl)) {
    throw 'Falta ERP_API_HEALTH_URL para comprobar que la API desplegada usa la misma base actualizada.'
}
$health = Invoke-RestMethod -Uri $HealthUrl -TimeoutSec 30
if ($health.status -ne 'ok' -or [int]$health.migrations -lt $migrations.Count) {
    throw "La API remota no confirmó la migración: status=$($health.status), migrations=$($health.migrations)."
}

Write-Host "Base desplegada verificada: $($health.migrations) migraciones, última $latestMigration."
