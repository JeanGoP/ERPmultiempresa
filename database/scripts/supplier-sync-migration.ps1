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
    $migration='053_supplier_zeus_sync'
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
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='053_supplier_zeus_sync') THROW 51740,'Migracion no registrada',1;
IF OBJECT_ID('core.ZeusProveedorEnvio','U') IS NULL THROW 51741,'Tabla no encontrada',1;
IF (SELECT COUNT(*) FROM sys.security_predicates WHERE target_object_id=OBJECT_ID('core.ZeusProveedorEnvio'))<>3 THROW 51741,'RLS incompleta',1;
IF NOT EXISTS(SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID('core.ZeusProveedorEnvio') AND name='FK_ZeusProveedorEnvio_Tercero' AND is_disabled=0 AND is_not_trusted=0) THROW 51741,'FK de proveedor no verificada',1;
SELECT name FROM sys.columns WHERE object_id=OBJECT_ID('core.ZeusProveedorEnvio');
"@
    $verified=New-Object System.Data.DataTable;$verified.Load($command.ExecuteReader())
    $verified | Format-Table -Wrap
    Write-Output 'Verificado en remoto: migracion 053, tabla, FK y tres predicados RLS. No se modificaron registros en Zeus.'
} finally {$connection.Dispose()}
