param([string]$Instance='(localdb)\MSSQLLocalDB',[int]$Workers=20,[int]$OperationsPerWorker=250)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$started=Get-Date
& (Join-Path $root 'database\scripts\check-concurrency.ps1') -Instance $Instance -Workers $Workers -OperationsPerWorker $OperationsPerWorker
if($LASTEXITCODE-ne 0){throw 'La prueba de volumen concurrente fallo.'}
$seconds=((Get-Date)-$started).TotalSeconds;$operations=$Workers*$OperationsPerWorker
[ordered]@{workers=$Workers;operations=$operations;seconds=[math]::Round($seconds,2);operationsPerSecond=[math]::Round($operations/[math]::Max($seconds,0.01),2);result='OK'}|ConvertTo-Json
