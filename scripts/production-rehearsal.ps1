param([string]$DatabaseName='NexoErpDev',[string]$Instance='(localdb)\MSSQLLocalDB',[switch]$SkipVolume)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$started=Get-Date
Push-Location $root
try{
    npm run test:all;if($LASTEXITCODE-ne 0){throw 'Fallo test:all.'}
    npm run db:check;if($LASTEXITCODE-ne 0){throw 'Fallo db:check.'}
    npm run api:smoke;if($LASTEXITCODE-ne 0){throw 'Fallo api:smoke.'}
    $backupJson=& (Join-Path $root 'database\scripts\backup-database.ps1') -DatabaseName $DatabaseName -Instance $Instance
    $backup=$backupJson|ConvertFrom-Json
    & (Join-Path $root 'database\scripts\verify-restore.ps1') -BackupPath $backup.backup -Instance $Instance
    if(!$SkipVolume){& (Join-Path $root 'tests\production-volume.ps1') -Instance $Instance;if($LASTEXITCODE-ne 0){throw 'Fallo la prueba de volumen.'}}
    [ordered]@{result='TECHNICALLY_READY';startedAt=$started.ToUniversalTime().ToString('o');finishedAt=(Get-Date).ToUniversalTime().ToString('o');backup=$backup.backup;formalApprovalRequired=$true}|ConvertTo-Json
}
finally{Pop-Location}
