param(
    [string]$DatabaseName = 'NexoErpDev',
    [string]$Instance = '(localdb)\MSSQLLocalDB'
)

$ErrorActionPreference = 'Stop'
Write-Warning 'Este comando actualiza únicamente SQL Server LocalDB. No aplica migraciones a la base desplegada.'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$databaseFolder = Join-Path $projectRoot 'database\local'
$migrationFolder = Join-Path $projectRoot 'database\migrations'

New-Item -ItemType Directory -Force -Path $databaseFolder | Out-Null
sqllocaldb start MSSQLLocalDB | Out-Null

$dataFile = (Join-Path $databaseFolder "$DatabaseName.mdf").Replace("'", "''")
$logFile = (Join-Path $databaseFolder "${DatabaseName}_log.ldf").Replace("'", "''")
$safeDatabaseName = $DatabaseName.Replace(']', ']]')
$createDatabase = @"
IF DB_ID(N'$($DatabaseName.Replace("'", "''"))') IS NULL
BEGIN
    CREATE DATABASE [$safeDatabaseName]
    ON PRIMARY (NAME=N'$safeDatabaseName', FILENAME=N'$dataFile')
    LOG ON (NAME=N'${safeDatabaseName}_log', FILENAME=N'$logFile');
END;
"@

& sqlcmd -S $Instance -E -b -Q $createDatabase
if ($LASTEXITCODE -ne 0) { throw 'No fue posible crear o abrir la base local.' }

Get-ChildItem -LiteralPath $migrationFolder -Filter '*.sql' | Sort-Object Name | ForEach-Object {
    Write-Host "Aplicando $($_.Name)..."
    & sqlcmd -S $Instance -E -b -d $DatabaseName -i $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "Falló la migración $($_.Name)." }
}

Write-Host "Base LOCAL $DatabaseName actualizada correctamente. Producción no fue modificada."
