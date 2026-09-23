$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$name='RepairMkmTest_'+[guid]::NewGuid().ToString('N')
if($name -notmatch '^RepairMkmTest_[a-f0-9]{32}$'){throw 'Nombre invalido'}
$master=New-Object System.Data.SqlClient.SqlConnection('Server=(localdb)\MSSQLLocalDB;Database=master;Integrated Security=True')
$master.Open();$db=$null
function Exec($c,$sql){$q=$c.CreateCommand();$q.CommandText=$sql;$q.CommandTimeout=60;try{[void]$q.ExecuteNonQuery()}finally{$q.Dispose()}}
try{
 Exec $master "CREATE DATABASE [$name]"
 $db=New-Object System.Data.SqlClient.SqlConnection("Server=(localdb)\MSSQLLocalDB;Database=$name;Integrated Security=True");$db.Open()
 Exec $db @'
 EXEC('CREATE SCHEMA core');EXEC('CREATE SCHEMA comp');EXEC('CREATE SCHEMA inv');EXEC('CREATE SCHEMA cxp');EXEC('CREATE SCHEMA audit');
 CREATE TABLE core.Empresa(EmpresaId bigint,Codigo varchar(20),RazonSocial nvarchar(200));INSERT core.Empresa VALUES(3,'01','MOTOCENTRO SA');
 CREATE TABLE comp.DocumentoProveedor(EmpresaId bigint,DocumentoProveedorId bigint,NumeroDocumento nvarchar(50),Estado varchar(20),ImpuestoTotal decimal(20,4),CargoTotal decimal(20,4),DescuentoTotal decimal(20,4),TotalPagar decimal(20,4),XmlOriginal nvarchar(max));
 INSERT comp.DocumentoProveedor VALUES(3,52,'MKM11928','CONTABILIZADO',6602651.43,0,0,41353448.43,'<Invoice><ID>MKM11928</ID><LegalMonetaryTotal><TaxInclusiveAmount>41353448.43</TaxInclusiveAmount></LegalMonetaryTotal><WithholdingTaxTotal><TaxSubtotal><TaxAmount>868769.93</TaxAmount><TaxCategory><Percent>2.5</Percent></TaxCategory></TaxSubtotal></WithholdingTaxTotal></Invoice>');
 CREATE TABLE comp.DocumentoProveedorLinea(EmpresaId bigint,DocumentoProveedorId bigint,DocumentoProveedorLineaId bigint,NumeroLinea int,Retencion decimal(20,4));
 INSERT comp.DocumentoProveedorLinea VALUES(3,52,184,1,289589.9767),(3,52,185,2,289589.9767),(3,52,186,3,289589.9767);
 CREATE TABLE inv.RecepcionMercancia(EmpresaId bigint,DocumentoProveedorId bigint,RecepcionMercanciaId bigint,Estado varchar(20));INSERT inv.RecepcionMercancia VALUES(3,52,37,'CONTABILIZADA');
 CREATE TABLE core.ZeusEnvio(EmpresaId bigint,RecepcionMercanciaId bigint,Estado varchar(30),Intentos int,Snapshot nvarchar(max),Documento varchar(10),Fuente varchar(2),Error nvarchar(2000),ActualizadoEnUtc datetime2);INSERT core.ZeusEnvio VALUES(3,37,'REQUIERE_REVISION',0,NULL,NULL,NULL,NULL,NULL);
 CREATE TABLE cxp.DocumentoPorPagar(EmpresaId bigint,DocumentoProveedorId bigint,DocumentoPorPagarId bigint,Estado varchar(20),ValorOriginal decimal(20,4),SaldoPendiente decimal(20,4),ActualizadoEnUtc datetime2);INSERT cxp.DocumentoPorPagar VALUES(3,52,17,'ABIERTA',41353448.43,41353448.43,NULL);
 CREATE TABLE cxp.MovimientoProveedor(EmpresaId bigint,DocumentoPorPagarId bigint,TipoMovimiento varchar(20),Cargo decimal(20,4),Abono decimal(20,4));INSERT cxp.MovimientoProveedor VALUES(3,17,'FACTURA',41353448.43,0);
 CREATE TABLE audit.Evento(EmpresaId bigint,UsuarioId bigint NULL,Operacion varchar(80),Entidad varchar(100),EntidadId nvarchar(100),Motivo nvarchar(500),ValoresAnteriores nvarchar(max),ValoresPosteriores nvarchar(max),AplicacionOrigen nvarchar(100));
'@
 Exec $db "UPDATE comp.DocumentoProveedor SET XmlOriginal=N'<?xml version=""1.0"" encoding=""UTF-8""?>'+XmlOriginal"
 $script=[IO.File]::ReadAllText((Join-Path $root 'database/scripts/repair-mkm11928-retention.sql'))
 function Reject($sql,$expected){try{Exec $db $sql;throw 'Acepto correccion insegura'}catch{if($_.Exception.Message -notlike "*$expected*"){throw}}}
 Exec $db "UPDATE core.ZeusEnvio SET Intentos=1"
 Reject $script 'envio Zeus cambio'
 Exec $db "UPDATE core.ZeusEnvio SET Intentos=0;INSERT cxp.MovimientoProveedor VALUES(3,17,'PAGO',0,100)"
 Reject $script 'pagos/aplicaciones'
 Exec $db "DELETE cxp.MovimientoProveedor WHERE TipoMovimiento='PAGO'"
 Reject ($script.Replace('COMMIT;',"THROW 52096,'FALLO_SIMULADO',1;")) 'FALLO_SIMULADO'
 Exec $db "IF (SELECT TotalPagar FROM comp.DocumentoProveedor)<>41353448.43 OR EXISTS(SELECT 1 FROM audit.Evento) THROW 52099,'Rollback incompleto',1;"
 Exec $db $script
 Exec $db $script
 Exec $db @'
 IF (SELECT TotalPagar FROM comp.DocumentoProveedor)<>40484678.50 THROW 52099,'Neto incorrecto',1;
 IF (SELECT SUM(Retencion) FROM comp.DocumentoProveedorLinea)<>868769.93 THROW 52099,'Retencion incorrecta',1;
 IF (SELECT SaldoPendiente FROM cxp.DocumentoPorPagar)<>40484678.50 OR (SELECT Cargo FROM cxp.MovimientoProveedor)<>40484678.50 THROW 52099,'Cartera incorrecta',1;
 IF (SELECT COUNT(*) FROM audit.Evento)<>1 THROW 52099,'Auditoria incorrecta',1;
 IF EXISTS(SELECT 1 FROM core.ZeusEnvio WHERE Estado<>'REQUIERE_REVISION' OR Intentos<>0) THROW 52099,'Se encolo sin autorizacion',1;
'@
 Write-Host 'OK: bloqueo por intento Zeus y pagos, rollback, correccion exacta, auditoria e idempotencia sin reenvio.'
}finally{
 if($db){$db.Dispose()};[System.Data.SqlClient.SqlConnection]::ClearAllPools()
 Exec $master "IF DB_ID(N'$name') IS NOT NULL BEGIN ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$name]; END"
 $master.Dispose()
}
