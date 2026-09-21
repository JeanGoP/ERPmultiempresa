param([switch]$Apply)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$envLine=Get-Content -LiteralPath (Join-Path $projectRoot '.env') | Where-Object {$_ -match '^\s*ConnectionStrings__NexoErp\s*='} | Select-Object -First 1
if(-not $envLine){throw 'Falta la conexion privada del ERP.'}
$connection=New-Object System.Data.SqlClient.SqlConnection (($envLine -split '=',2)[1].Trim().Trim('"').Trim("'"))
try {
    $connection.Open()
    if($connection.DataSource -match '(?i)localdb'){throw 'Esta verificacion requiere la base remota, no LocalDB.'}
    Write-Output ('Destino ERP: '+$connection.DataSource+' / '+$connection.Database)
    $command=$connection.CreateCommand();$command.CommandTimeout=120
    $command.CommandText='SELECT MigrationId FROM core.SchemaMigration ORDER BY MigrationId'
    $table=New-Object System.Data.DataTable;$table.Load($command.ExecuteReader())
    $applied=@($table.Rows | ForEach-Object {$_.MigrationId})
    Write-Output ('Migraciones aplicadas: '+$applied.Count+'; ultima: '+($applied | Select-Object -Last 1))
    $migration='049_zeus_integration'
    $previous=Get-ChildItem -LiteralPath (Join-Path $projectRoot 'database/migrations') -Filter '*.sql' | Where-Object {$_.BaseName -lt $migration}
    foreach($file in $previous){if($file.BaseName -notin $applied){throw ('Prerequisito pendiente: '+$file.BaseName)}}
    if($migration -notin $applied){
        if(-not $Apply){Write-Output "Pendiente: $migration";return}
        $sql=[IO.File]::ReadAllText((Join-Path $projectRoot "database/migrations/$migration.sql"))
        try {
            foreach($batch in [regex]::Split($sql,'(?im)^\s*GO\s*$')){
                if([string]::IsNullOrWhiteSpace($batch)){continue}
                $command.CommandText=$batch;[void]$command.ExecuteNonQuery()
            }
        } catch {
            try {$command.CommandText='IF @@TRANCOUNT>0 ROLLBACK';[void]$command.ExecuteNonQuery()}catch{}
            throw
        }
        Write-Output "Aplicada: $migration"
    } else {Write-Output 'La migracion ya estaba aplicada; no se ejecuto nuevamente.'}
    $command.CommandText=@"
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='049_zeus_integration') THROW 51720,'Migracion no registrada',1;
IF OBJECT_ID('core.ZeusConfiguracion','U') IS NULL OR OBJECT_ID('core.ZeusEnvio','U') IS NULL OR OBJECT_ID('inv.TR_RecepcionMercancia_Zeus','TR') IS NULL THROW 51721,'Faltan objetos Zeus',1;
IF (SELECT COUNT(*) FROM sys.security_predicates WHERE target_object_id IN(OBJECT_ID('core.ZeusConfiguracion'),OBJECT_ID('core.ZeusEnvio')))<>6 THROW 51722,'Faltan predicados de seguridad',1;
SELECT 'core.ZeusConfiguracion' Objeto,COUNT(*) Filas FROM core.ZeusConfiguracion
UNION ALL SELECT 'core.ZeusEnvio',COUNT(*) FROM core.ZeusEnvio;
"@
    $verified=New-Object System.Data.DataTable;$verified.Load($command.ExecuteReader())
    $verified | Format-Table -AutoSize | Out-String | Write-Output
    Write-Output 'Verificados en remoto: registro de migracion, tablas, trigger y seis predicados RLS.'
} finally {$connection.Dispose()}
