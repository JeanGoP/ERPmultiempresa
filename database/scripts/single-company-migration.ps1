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
    $migration='050_single_company_users'
    $previous=Get-ChildItem -LiteralPath (Join-Path $projectRoot 'database/migrations') -Filter '*.sql' | Where-Object {$_.BaseName -lt $migration}
    foreach($file in $previous){if($file.BaseName -notin $applied){throw ('Prerequisito pendiente: '+$file.BaseName)}}
    $command.CommandText='SELECT COUNT(*) FROM (SELECT u.UsuarioId FROM seg.Usuario u JOIN seg.UsuarioEmpresaRol ur ON ur.UsuarioId=u.UsuarioId WHERE u.EsSuperAdministrador=0 AND u.Activo=1 AND ur.Activo=1 GROUP BY u.UsuarioId HAVING COUNT(DISTINCT ur.EmpresaId)>1) x'
    $conflicts=[int]$command.ExecuteScalar();Write-Output "Usuarios activos con asignacion multiple preexistente: $conflicts. No se reasignaran automaticamente."
    $command.CommandText='SELECT COUNT_BIG(*) FROM seg.UsuarioEmpresaRol';$before=$command.ExecuteScalar()
    if($migration -notin $applied){
        if(-not $Apply){Write-Output "Pendiente: $migration";return}
        $sql=[IO.File]::ReadAllText((Join-Path $projectRoot "database/migrations/$migration.sql"))
        try {foreach($batch in [regex]::Split($sql,'(?im)^\s*GO\s*$')){if([string]::IsNullOrWhiteSpace($batch)){continue};$command.CommandText=$batch;[void]$command.ExecuteNonQuery()}}
        catch {try{$command.CommandText='IF @@TRANCOUNT>0 ROLLBACK';[void]$command.ExecuteNonQuery()}catch{};throw}
        Write-Output "Aplicada: $migration"
    } else {Write-Output 'Ya aplicada; no se ejecuto nuevamente.'}
    $command.CommandText=@"
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='050_single_company_users') THROW 51732,'Migracion no registrada',1;
IF NOT EXISTS(SELECT 1 FROM sys.triggers WHERE object_id=OBJECT_ID('seg.TR_UsuarioEmpresaRol_EmpresaUnica') AND is_disabled=0) THROW 51733,'Trigger no activo',1;
SELECT COUNT_BIG(*) FROM seg.UsuarioEmpresaRol;
"@
    $after=$command.ExecuteScalar();if($before -ne $after){throw 'Cambio el numero de asignaciones durante la verificacion; revisar actividad concurrente.'}
    Write-Output "Verificado en remoto: migracion 050 y trigger activo. Asignaciones conservadas: $after."
} finally {$connection.Dispose()}
