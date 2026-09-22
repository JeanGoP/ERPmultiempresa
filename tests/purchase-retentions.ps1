$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$db='NexoRetentionTest_'+[Guid]::NewGuid().ToString('N')
$master=New-Object System.Data.SqlClient.SqlConnection 'Server=(localdb)\MSSQLLocalDB;Database=master;Integrated Security=True;TrustServerCertificate=True'
$c=$null
try {
    $master.Open();$q=$master.CreateCommand();$q.CommandText="CREATE DATABASE [$db]";[void]$q.ExecuteNonQuery()
    $c=New-Object System.Data.SqlClient.SqlConnection "Server=(localdb)\MSSQLLocalDB;Database=$db;Integrated Security=True;TrustServerCertificate=True";$c.Open()
    $q=$c.CreateCommand()
    foreach($sql in @('CREATE SCHEMA core','CREATE SCHEMA comp',@'
CREATE TABLE core.SchemaMigration(MigrationId nvarchar(100) PRIMARY KEY,Descripcion nvarchar(500));
CREATE TABLE comp.DocumentoProveedorLinea(DocumentoProveedorLineaId bigint PRIMARY KEY,EmpresaId bigint,DocumentoProveedorId bigint,NumeroLinea int,Clasificacion varchar(30),TotalNeto decimal(20,4),Impuesto decimal(20,4),Retencion decimal(20,4));
INSERT comp.DocumentoProveedorLinea VALUES(1,1,10,1,'INVENTARIO',100,19,0),(2,1,10,2,'SERVICIO_GASTO',200,38,0),(3,2,10,1,'INVENTARIO',100,19,0),(4,1,11,1,'INVENTARIO',100,19,0);
'@)) {$q.CommandText=$sql;[void]$q.ExecuteNonQuery()}
    $migration=Get-Content -Raw -LiteralPath (Join-Path $root 'database/migrations/054_purchase_inventory_retentions.sql')
    foreach($pass in 1..2){foreach($batch in [regex]::Split($migration,'(?im)^\s*GO\s*$')){if($batch.Trim()){$q.CommandText=$batch;[void]$q.ExecuteNonQuery()}}}
    $q.CommandText='EXEC comp.usp_GuardarRetencionesDocumento 1,10,N''[{"numeroLinea":1,"retencion":2.5},{"numeroLinea":2,"retencion":5}]'''
    [void]$q.ExecuteNonQuery()
    $q.CommandText='SELECT SUM(Retencion) FROM comp.DocumentoProveedorLinea WHERE EmpresaId=1 AND DocumentoProveedorId=10'
    if([decimal]$q.ExecuteScalar() -ne 7.5){throw 'No guardo retenciones de mercancia y servicios'}
    $q.CommandText='SELECT SUM(Retencion) FROM comp.DocumentoProveedorLinea WHERE EmpresaId<>1 OR DocumentoProveedorId<>10'
    if([decimal]$q.ExecuteScalar() -ne 0){throw 'Modifico otra empresa o factura'}
    foreach($json in @('[{"numeroLinea":1,"retencion":120}]','[{"numeroLinea":1,"retencion":-1}]','[{"numeroLinea":3,"retencion":1}]','[{"numeroLinea":1}]','[{"retencion":1}]','[{"numeroLinea":1,"retencion":1},{"numeroLinea":1,"retencion":2}]','{}','null','[{"numeroLinea":1,"retencion":3},{"numeroLinea":99,"retencion":1}]')) {
        $q.CommandText='EXEC comp.usp_GuardarRetencionesDocumento 1,10,@J';[void]$q.Parameters.AddWithValue('@J',$json)
        $rejected=$false;try{[void]$q.ExecuteNonQuery()}catch [System.Data.SqlClient.SqlException]{if($_.Exception.Number -notin @(52120,52121)){throw};$rejected=$true}finally{$q.Parameters.Clear()}
        if(-not $rejected){throw 'Acepto retencion invalida'}
    }
    $q.CommandText='SELECT SUM(Retencion) FROM comp.DocumentoProveedorLinea WHERE EmpresaId=1 AND DocumentoProveedorId=10'
    if([decimal]$q.ExecuteScalar() -ne 7.5){throw 'Una solicitud rechazada altero importes'}
    $q.CommandText="SELECT COUNT(*) FROM core.SchemaMigration WHERE MigrationId='054_purchase_inventory_retentions'"
    if([int]$q.ExecuteScalar() -ne 1){throw 'Migracion no idempotente'}
    Write-Output 'Correcto: mercancia y servicios, aislamiento por empresa y factura, limites, datos incompletos, duplicados, rechazo sin escrituras parciales y migracion idempotente.'
} finally {
    if($c){$c.Dispose()};[System.Data.SqlClient.SqlConnection]::ClearAllPools()
    if($master.State -eq 'Open'){$q=$master.CreateCommand();$q.CommandText="IF DB_ID('$db') IS NOT NULL BEGIN ALTER DATABASE [$db] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$db]; END";[void]$q.ExecuteNonQuery()};$master.Dispose()
}
