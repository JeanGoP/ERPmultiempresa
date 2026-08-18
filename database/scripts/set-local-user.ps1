param(
    [Parameter(Mandatory=$true)][string]$Correo,
    [Parameter(Mandatory=$true)][securestring]$Password,
    [Parameter(Mandatory=$true)][string]$NombreCompleto,
    [Parameter(Mandatory=$true)][string]$EmpresaCodigo,
    [string]$DatabaseName='NexoErpDev',
    [string]$Instance='(localdb)\MSSQLLocalDB'
)

$ErrorActionPreference='Stop'
$passwordPointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
try {
    $plainPassword=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
    $salt=New-Object byte[] 32
    $random=[Security.Cryptography.RandomNumberGenerator]::Create()
    try { $random.GetBytes($salt) } finally { $random.Dispose() }
    $derive=[Security.Cryptography.Rfc2898DeriveBytes]::new($plainPassword,$salt,210000,[Security.Cryptography.HashAlgorithmName]::SHA512)
    try { $hash=$derive.GetBytes(64) } finally { $derive.Dispose() }
} finally {
    if($passwordPointer -ne [IntPtr]::Zero){ [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer) }
    $plainPassword=$null
}

$saltHex=([BitConverter]::ToString($salt)).Replace('-','')
$hashHex=([BitConverter]::ToString($hash)).Replace('-','')
$safeEmail=$Correo.Replace("'","''")
$safeName=$NombreCompleto.Replace("'","''")
$safeCompany=$EmpresaCodigo.Replace("'","''")
$sql=@"
SET XACT_ABORT ON;
BEGIN TRANSACTION;
DECLARE @EmpresaId bigint=(SELECT EmpresaId FROM core.Empresa WHERE Codigo=N'$safeCompany');
IF @EmpresaId IS NULL THROW 52000,'La empresa indicada no existe.',1;
DECLARE @UsuarioId bigint=(SELECT UsuarioId FROM seg.Usuario WHERE Correo=N'$safeEmail');
IF @UsuarioId IS NULL
BEGIN
  INSERT seg.Usuario(Correo,NombreCompleto) VALUES(N'$safeEmail',N'$safeName');
  SET @UsuarioId=SCOPE_IDENTITY();
END
ELSE UPDATE seg.Usuario SET NombreCompleto=N'$safeName',Activo=1 WHERE UsuarioId=@UsuarioId;
MERGE seg.UsuarioCredencial AS t
USING(SELECT @UsuarioId UsuarioId) s ON s.UsuarioId=t.UsuarioId
WHEN MATCHED THEN UPDATE SET PasswordHash=0x$hashHex,PasswordSalt=0x$saltHex,Iteraciones=210000,IntentosFallidos=0,BloqueadoHastaUtc=NULL,PasswordActualizadoEnUtc=SYSUTCDATETIME()
WHEN NOT MATCHED THEN INSERT(UsuarioId,PasswordHash,PasswordSalt,Iteraciones) VALUES(@UsuarioId,0x$hashHex,0x$saltHex,210000);
DECLARE @RolId bigint=(SELECT RolId FROM seg.Rol WHERE Codigo='ADMIN');
IF @RolId IS NULL BEGIN INSERT seg.Rol(Codigo,Nombre) VALUES('ADMIN',N'Administrador'); SET @RolId=SCOPE_IDENTITY(); END;
IF NOT EXISTS(SELECT 1 FROM seg.UsuarioEmpresaRol WHERE EmpresaId=@EmpresaId AND UsuarioId=@UsuarioId AND RolId=@RolId)
  INSERT seg.UsuarioEmpresaRol(EmpresaId,UsuarioId,RolId) VALUES(@EmpresaId,@UsuarioId,@RolId);
ELSE UPDATE seg.UsuarioEmpresaRol SET Activo=1 WHERE EmpresaId=@EmpresaId AND UsuarioId=@UsuarioId AND RolId=@RolId;
COMMIT;
"@

& sqlcmd -S $Instance -E -b -d $DatabaseName -Q $sql
if($LASTEXITCODE -ne 0){ throw 'No fue posible crear o actualizar el usuario local.' }
Write-Host "Usuario $Correo habilitado para la empresa $EmpresaCodigo."
