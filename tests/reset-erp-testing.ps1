param([string]$Instance='(localdb)\MSSQLLocalDB')
$ErrorActionPreference='Stop'
if($Instance -ne '(localdb)\MSSQLLocalDB'){throw 'Esta prueba solo permite LocalDB.'}
$root=Split-Path $PSScriptRoot -Parent
$name='ResetErpTest_'+[guid]::NewGuid().ToString('N')
if($name -notmatch '^ResetErpTest_[a-f0-9]{32}$'){throw 'Nombre de prueba invalido'}
$master=New-Object System.Data.SqlClient.SqlConnection("Server=$Instance;Database=master;Integrated Security=True")
$master.Open()
function Execute($connection,[string]$sql){$q=$connection.CreateCommand();$q.CommandTimeout=180;$q.CommandText=$sql;try{[void]$q.ExecuteNonQuery()}finally{$q.Dispose()}}
function Scalar($connection,[string]$sql){$q=$connection.CreateCommand();$q.CommandText=$sql;try{$q.ExecuteScalar()}finally{$q.Dispose()}}
$db=$null
try{
    Execute $master "CREATE DATABASE [$name]"
    $db=New-Object System.Data.SqlClient.SqlConnection("Server=$Instance;Database=$name;Integrated Security=True")
    $db.Open()
    foreach($file in Get-ChildItem (Join-Path $root 'database/migrations') -Filter '*.sql' | Sort-Object Name){
        foreach($batch in [regex]::Split([IO.File]::ReadAllText($file.FullName),'(?im)^\s*GO\s*$')){if($batch.Trim()){Execute $db $batch}}
    }
    Execute $db @"
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES('MOTO','123','MOTOCENTRO SA'),('OTRA','456','OTRA EMPRESA');
INSERT seg.Usuario(Correo,NombreCompleto,EsSuperAdministrador) VALUES('super@test.invalid','Super',1),('otro@test.invalid','Otro',0);
INSERT seg.UsuarioCredencial(UsuarioId,PasswordHash,PasswordSalt,Iteraciones) SELECT UsuarioId,0x1234,0x5678,210000 FROM seg.Usuario;
INSERT core.EmpresaConfiguracion(EmpresaId) SELECT EmpresaId FROM core.Empresa;
INSERT ter.Tercero(EmpresaId,NumeroIdentificacion,RazonSocial,EsProveedor) SELECT EmpresaId,'999','Proveedor prueba',1 FROM core.Empresa;
INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) SELECT EmpresaId,'UND','Unidad','U' FROM core.Empresa;
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,UnidadBaseId) SELECT EmpresaId,'A1','Articulo prueba','INVENTARIO',UnidadMedidaId FROM inv.UnidadMedida;
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) SELECT EmpresaId,'01','Bodega prueba' FROM core.Empresa;
INSERT core.Sucursal(EmpresaId,Codigo,Nombre) SELECT EmpresaId,'01','Sucursal prueba' FROM core.Empresa;
INSERT core.ZeusConfiguracion(EmpresaId,Configuracion,ActualizadoPor) SELECT EmpresaId,'{}',1 FROM core.Empresa;
INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad) SELECT EmpresaId,2,'PRUEBA','test' FROM core.Empresa;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
"@
    $script=[IO.File]::ReadAllText((Join-Path $root 'database/scripts/reset-erp-testing.sql'))
    Execute $db $script
    if((Scalar $db 'SELECT COUNT(*) FROM core.Empresa') -ne 2){throw 'Vista previa modifico empresas'}
    if((Scalar $db "SELECT SESSION_CONTEXT(N'BypassRls')") -isnot [DBNull]){throw 'Vista previa no restaura RLS'}
    $server=([string](Scalar $db "SELECT CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))")).Replace("'","''")
    $confirmed=$script.Replace("N'ERPMontelibano'","N'$name'").Replace("N'CAMBIAR-SERVIDOR'","N'$server'").Replace("N'CAMBIAR-CODIGO'","N'MOTO'").Replace('@SuperAdminId bigint = NULL','@SuperAdminId bigint = 1').Replace("@Confirmacion nvarchar(100) = N'SOLO-VISTA-PREVIA'","@Confirmacion nvarchar(100) = N'BORRAR-TODO-EXCEPTO-MOTOCENTRO'").Replace('@RespaldoVerificado bit = 0, @MantenimientoConfirmado bit = 0','@RespaldoVerificado bit = 1, @MantenimientoConfirmado bit = 1')
    function Reject([string]$sql,[string]$expected){try{Execute $db $sql;throw 'Acepto un reinicio invalido'}catch{if($_.Exception.Message -notlike "*$expected*"){throw}}}
    Reject ($confirmed.Replace("@BaseEsperada sysname = N'$name'","@BaseEsperada sysname = N'BASE_INCORRECTA'")) 'Servidor o base distintos'
    Reject ($confirmed.Replace('@SuperAdminId bigint = 1','@SuperAdminId bigint = 2')) 'superadministrador activo'
    Execute $db 'CREATE TABLE dbo.TablaNoRevisada(Id int)'
    Reject $confirmed 'tablas no revisadas'
    Execute $db 'DROP TABLE dbo.TablaNoRevisada'
    $triggersBefore=Scalar $db 'SELECT COUNT(*) FROM sys.triggers WHERE is_disabled=0'
    Reject ($confirmed.Replace('INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);',"THROW 52091,'FALLO_SIMULADO',1;")) 'FALLO_SIMULADO'
    if((Scalar $db 'SELECT COUNT(*) FROM core.Empresa') -ne 2 -or (Scalar $db 'SELECT COUNT(*) FROM sys.triggers WHERE is_disabled=0') -ne $triggersBefore){throw 'Rollback no restauro datos/triggers'}
    if((Scalar $db 'SELECT COUNT(*) FROM sys.foreign_keys WHERE is_disabled=1 OR is_not_trusted=1') -ne 0){throw 'Rollback no restauro FK'}
    Execute $db $confirmed
    Execute $db @"
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
IF (SELECT COUNT(*) FROM core.Empresa)<>1 OR NOT EXISTS(SELECT 1 FROM core.Empresa WHERE Codigo='MOTO') THROW 52099,'Empresa no conservada',1;
IF (SELECT COUNT(*) FROM seg.Usuario)<>1 OR NOT EXISTS(SELECT 1 FROM seg.UsuarioCredencial WHERE UsuarioId=1 AND PasswordHash=0x1234 AND PasswordSalt=0x5678) THROW 52099,'Usuario o credencial alterados',1;
IF EXISTS(SELECT 1 FROM ter.Tercero) OR EXISTS(SELECT 1 FROM inv.Articulo) OR EXISTS(SELECT 1 FROM inv.Bodega) OR EXISTS(SELECT 1 FROM core.ZeusConfiguracion) THROW 52099,'Quedaron maestros',1;
IF (SELECT COUNT(*) FROM audit.Evento)<>1 OR NOT EXISTS(SELECT 1 FROM audit.Evento WHERE Operacion='REINICIO_TOTAL_PRUEBAS') THROW 52099,'Auditoria incorrecta',1;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration) OR NOT EXISTS(SELECT 1 FROM seg.Permiso) THROW 52099,'Infraestructura borrada',1;
IF EXISTS(SELECT 1 FROM sys.foreign_keys WHERE is_disabled=1 OR is_not_trusted=1) THROW 52099,'FK invalidas',1;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
"@
    if((Scalar $db 'SELECT COUNT(*) FROM sys.triggers WHERE is_disabled=0') -ne $triggersBefore){throw 'Triggers no restaurados'}
    Execute $db $confirmed
    Write-Host 'OK: esquema completo, vista previa, destinos invalidos, usuario incorrecto, tablas desconocidas, rollback, credencial conservada, integridad y segunda ejecucion.'
}finally{
    if($db){$db.Dispose()}
    [System.Data.SqlClient.SqlConnection]::ClearAllPools()
    Execute $master "IF DB_ID(N'$name') IS NOT NULL BEGIN ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$name]; END"
    $master.Dispose()
}
