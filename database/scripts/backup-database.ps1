param(
    [string]$DatabaseName = 'NexoErpDev',
    [string]$Instance = '(localdb)\MSSQLLocalDB',
    [string]$OutputDirectory
)
$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if([string]::IsNullOrWhiteSpace($OutputDirectory)){$OutputDirectory=Join-Path $projectRoot 'database\backups'}
New-Item -ItemType Directory -Force -Path $OutputDirectory|Out-Null
$resolved=(Resolve-Path $OutputDirectory).Path
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath=Join-Path $resolved "$DatabaseName-$stamp.bak"
$safeDb=$DatabaseName.Replace(']',']]');$safePath=$backupPath.Replace("'","''")
$sql="BACKUP DATABASE [$safeDb] TO DISK=N'$safePath' WITH COPY_ONLY,INIT,CHECKSUM,STATS=10; RESTORE VERIFYONLY FROM DISK=N'$safePath' WITH CHECKSUM;"
& sqlcmd -S $Instance -E -b -Q $sql | Out-Host
if($LASTEXITCODE-ne 0){throw 'El respaldo o RESTORE VERIFYONLY fallaron.'}
$file=Get-Item -LiteralPath $backupPath
$hash=(Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash
$report=[ordered]@{database=$DatabaseName;instance=$Instance;backup=$file.FullName;bytes=$file.Length;sha256=$hash;verified=$true;createdAtUtc=(Get-Date).ToUniversalTime().ToString('o')}
$reportPath="$backupPath.json";$report|ConvertTo-Json|Set-Content -LiteralPath $reportPath -Encoding utf8
$report|ConvertTo-Json
