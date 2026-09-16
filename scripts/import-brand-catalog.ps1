param(
    [Parameter(Mandatory=$true)][string]$Workbook,
    [Parameter(Mandatory=$true)][string]$Python,
    [Parameter(Mandatory=$true)][long]$EmpresaId,
    [Parameter(Mandatory=$true)][string]$ExpectedNit,
    [Parameter(Mandatory=$true)][string]$ExpectedDatabase
)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$json=(& $Python (Join-Path $PSScriptRoot 'read-brand-catalog.py') $Workbook) -join "`n"
if($LASTEXITCODE -ne 0){throw 'No se pudo validar el Excel. No se ha escrito en la base.'}
$catalog=$json | ConvertFrom-Json
$line=Get-Content (Join-Path $root '.env') | Where-Object {$_ -match '^\s*ConnectionStrings__NexoErp\s*='} | Select-Object -First 1
if(-not $line){throw 'Falta la conexión privada en .env.'}
$connection=New-Object System.Data.SqlClient.SqlConnection (($line -split '=',2)[1].Trim().Trim('"').Trim("'"))
try {
    $connection.Open()
    if($connection.Database -ne $ExpectedDatabase){throw 'La base conectada no coincide con la esperada.'}
    $command=$connection.CreateCommand()
    $command.CommandTimeout=120
    $command.CommandText=@'
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET XACT_ABORT ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=0;
EXEC sys.sp_set_session_context @key=N'EmpresaId',@value=@EmpresaId;
IF NOT EXISTS(SELECT 1 FROM core.Empresa WHERE EmpresaId=@EmpresaId AND Nit=@Nit)
    THROW 51600,'La empresa y su NIT no coinciden. No se importó el catálogo.',1;
BEGIN TRANSACTION;
DECLARE @Filas TABLE(Referencia nvarchar(100) PRIMARY KEY,Descripcion nvarchar(300),Marca nvarchar(100),Linea nvarchar(100),Categoria nvarchar(100),Habilitada bit,Motivo nvarchar(300),Fila int);
INSERT @Filas SELECT * FROM OPENJSON(@Json,'$.filas') WITH(
    Referencia nvarchar(100) '$.referencia',Descripcion nvarchar(300) '$.descripcion',Marca nvarchar(100) '$.marca',
    Linea nvarchar(100) '$.linea',Categoria nvarchar(100) '$.categoria',Habilitada bit '$.habilitada',Motivo nvarchar(300) '$.motivo',Fila int '$.fila');
-- Hold the tenant/reference range to make repeated imports idempotent.
DECLARE @Existentes int=(SELECT COUNT(*) FROM inv.CatalogoMarcaDescripcion WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId);
UPDATE c SET Descripcion=f.Descripcion,Marca=f.Marca,Linea=f.Linea,Categoria=f.Categoria,Habilitada=f.Habilitada,
    MotivoRevision=f.Motivo,ArchivoOrigen=JSON_VALUE(@Json,'$.archivo'),ArchivoSha256=JSON_VALUE(@Json,'$.sha256'),FilaOrigen=f.Fila,ActualizadoUtc=SYSUTCDATETIME()
FROM inv.CatalogoMarcaDescripcion c JOIN @Filas f ON f.Referencia=c.Referencia WHERE c.EmpresaId=@EmpresaId;
INSERT inv.CatalogoMarcaDescripcion(EmpresaId,Referencia,Descripcion,Marca,Linea,Categoria,Habilitada,MotivoRevision,ArchivoOrigen,ArchivoSha256,FilaOrigen)
SELECT @EmpresaId,f.Referencia,f.Descripcion,f.Marca,f.Linea,f.Categoria,f.Habilitada,f.Motivo,JSON_VALUE(@Json,'$.archivo'),JSON_VALUE(@Json,'$.sha256'),f.Fila
FROM @Filas f WHERE NOT EXISTS(SELECT 1 FROM inv.CatalogoMarcaDescripcion c WHERE c.EmpresaId=@EmpresaId AND c.Referencia=f.Referencia);
IF (SELECT COUNT(*) FROM inv.CatalogoMarcaDescripcion c JOIN @Filas f ON f.Referencia=c.Referencia WHERE c.EmpresaId=@EmpresaId AND c.ArchivoSha256=JSON_VALUE(@Json,'$.sha256'))<>(SELECT COUNT(*) FROM @Filas)
    THROW 51601,'No se pudo verificar la totalidad de la carga.',1;
-- Extend the normalized brand master without changing an existing manual rename.
INSERT inv.Marca(EmpresaId,Nombre)
SELECT @EmpresaId,MIN(c.Marca) FROM inv.CatalogoMarcaDescripcion c
WHERE c.EmpresaId=@EmpresaId AND c.Habilitada=1 AND c.MarcaId IS NULL
    AND NOT EXISTS(SELECT 1 FROM inv.Marca m WHERE m.EmpresaId=@EmpresaId AND m.Nombre=c.Marca COLLATE Latin1_General_100_CI_AI)
GROUP BY c.Marca COLLATE Latin1_General_100_CI_AI;
UPDATE c SET MarcaId=m.MarcaId FROM inv.CatalogoMarcaDescripcion c
JOIN inv.Marca m ON m.EmpresaId=c.EmpresaId AND m.Nombre=c.Marca COLLATE Latin1_General_100_CI_AI
WHERE c.EmpresaId=@EmpresaId AND c.Habilitada=1 AND c.MarcaId IS NULL;
COMMIT;
SELECT COUNT(*) AS Total,SUM(CASE WHEN Habilitada=1 THEN 1 ELSE 0 END) AS Habilitadas,
    SUM(CASE WHEN Habilitada=0 THEN 1 ELSE 0 END) AS Pendientes
FROM inv.CatalogoMarcaDescripcion WHERE EmpresaId=@EmpresaId;
'@
    $null=$command.Parameters.Add('@EmpresaId',[System.Data.SqlDbType]::BigInt);$command.Parameters['@EmpresaId'].Value=$EmpresaId
    $null=$command.Parameters.Add('@Nit',[System.Data.SqlDbType]::NVarChar,30);$command.Parameters['@Nit'].Value=$ExpectedNit
    $null=$command.Parameters.Add('@Json',[System.Data.SqlDbType]::NVarChar,-1);$command.Parameters['@Json'].Value=$json
    $reader=$command.ExecuteReader()
    while($reader.Read()){Write-Host "Empresa $EmpresaId / $ExpectedDatabase : $($reader['Total']) referencias, $($reader['Habilitadas']) habilitadas, $($reader['Pendientes']) pendientes."}
    $reader.Close()
} finally {$connection.Dispose()}
