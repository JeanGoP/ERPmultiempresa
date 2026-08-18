param(
    [Parameter(Mandatory=$true)][string]$BackupPath,
    [string]$Instance = '(localdb)\MSSQLLocalDB'
)
$ErrorActionPreference='Stop'
$backup=(Resolve-Path -LiteralPath $BackupPath).Path
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$databaseName="NexoErpRestoreQa_$PID";$safeDb=$databaseName.Replace(']',']]')
$dataPath=(Join-Path $projectRoot "database\local\$databaseName.mdf").Replace("'","''")
$logPath=(Join-Path $projectRoot "database\local\${databaseName}_log.ldf").Replace("'","''")
$safeBackup=$backup.Replace("'","''")
try{
    $rows=& sqlcmd -S $Instance -E -b -W -h -1 -s '|' -Q "RESTORE FILELISTONLY FROM DISK=N'$safeBackup';"
    if($LASTEXITCODE-ne 0){throw 'No fue posible leer el contenido del respaldo.'}
    $dataRow=$rows|Where-Object{$_ -match '\|D\|'}|Select-Object -First 1
    $logRow=$rows|Where-Object{$_ -match '\|L\|'}|Select-Object -First 1
    if(!$dataRow-or!$logRow){throw 'No se identificaron los archivos logicos del respaldo.'}
    $dataLogical=($dataRow-split '\|')[0].Trim().Replace("'","''");$logLogical=($logRow-split '\|')[0].Trim().Replace("'","''")
    $restore="RESTORE DATABASE [$safeDb] FROM DISK=N'$safeBackup' WITH MOVE N'$dataLogical' TO N'$dataPath',MOVE N'$logLogical' TO N'$logPath',RECOVERY; DBCC CHECKDB([$safeDb]) WITH NO_INFOMSGS; IF (SELECT COUNT(*) FROM [$safeDb].core.SchemaMigration)<38 THROW 52002,'El respaldo no contiene las migraciones productivas esperadas.',1;"
    & sqlcmd -S $Instance -E -b -Q $restore
    if($LASTEXITCODE-ne 0){throw 'La restauracion aislada o DBCC CHECKDB fallaron.'}
    [ordered]@{backup=$backup;restoredDatabase=$databaseName;integrity='OK';minimumMigrations=37;verifiedAtUtc=(Get-Date).ToUniversalTime().ToString('o')}|ConvertTo-Json
}
finally{
    $drop="IF DB_ID(N'$databaseName') IS NOT NULL BEGIN ALTER DATABASE [$safeDb] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;DROP DATABASE [$safeDb];END;"
    & sqlcmd -S $Instance -E -b -Q $drop|Out-Null
}
