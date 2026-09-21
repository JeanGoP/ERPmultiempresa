param([switch]$Apply)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$envLine=Get-Content -LiteralPath (Join-Path $projectRoot '.env') | Where-Object {$_ -match '^\s*ConnectionStrings__NexoErp\s*='} | Select-Object -First 1
if(-not $envLine){throw 'Falta la conexion privada del ERP.'}
$connection=New-Object System.Data.SqlClient.SqlConnection (($envLine -split '=',2)[1].Trim().Trim('"').Trim("'"))
try {
    $connection.Open()
    if($connection.DataSource -match '(?i)localdb'){throw 'Se requiere la base remota.'}
    Write-Output ('Destino ERP: '+$connection.DataSource+' / '+$connection.Database)
    $command=$connection.CreateCommand();$command.CommandTimeout=120
    $command.CommandText='SELECT MigrationId FROM core.SchemaMigration ORDER BY MigrationId'
    $table=New-Object System.Data.DataTable;$table.Load($command.ExecuteReader())
    $applied=@($table.Rows | ForEach-Object {$_.MigrationId})
    Write-Output ('Migraciones aplicadas: '+$applied.Count+'; ultima: '+($applied | Select-Object -Last 1))
    $migration='051_supplier_zeus_political_division'
    foreach($file in (Get-ChildItem -LiteralPath (Join-Path $projectRoot 'database/migrations') -Filter '*.sql' | Where-Object {$_.BaseName -lt $migration})) {
        if($file.BaseName -notin $applied){throw ('Prerequisito pendiente: '+$file.BaseName)}
    }
    if($migration -notin $applied){
        if(-not $Apply){Write-Output "Pendiente: $migration";return}
        $sql=[IO.File]::ReadAllText((Join-Path $projectRoot "database/migrations/$migration.sql"))
        try {foreach($batch in [regex]::Split($sql,'(?im)^\s*GO\s*$')){if([string]::IsNullOrWhiteSpace($batch)){continue};$command.CommandText=$batch;[void]$command.ExecuteNonQuery()}}
        catch {try{$command.CommandText='IF @@TRANCOUNT>0 ROLLBACK';[void]$command.ExecuteNonQuery()}catch{};throw}
        Write-Output "Aplicada: $migration"
    } else {Write-Output 'Ya aplicada; no se ejecuto nuevamente.'}
    $command.CommandText=@"
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='051_supplier_zeus_political_division') THROW 51740,'Migracion no registrada',1;
IF NOT EXISTS(SELECT 1 FROM sys.computed_columns WHERE object_id=OBJECT_ID('ter.Tercero') AND name='DivisionPoliticaZeus') THROW 51741,'Columna calculada no encontrada',1;
SELECT name,definition FROM sys.computed_columns WHERE object_id=OBJECT_ID('ter.Tercero') AND name='DivisionPoliticaZeus';
"@
    $verified=New-Object System.Data.DataTable;$verified.Load($command.ExecuteReader())
    $verified | Format-Table -Wrap
    Write-Output 'Verificado en remoto: migracion 051 y definicion de la columna calculada. No se modificaron registros en Zeus.'
} finally {$connection.Dispose()}
