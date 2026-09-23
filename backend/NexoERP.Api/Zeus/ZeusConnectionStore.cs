using System.Data;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;

namespace NexoERP.Api.Zeus;

public sealed record ZeusConnectionInput(string Servidor,string BaseDatos,string UsuarioSql,string? Password,
    string UsuarioContable,bool ConfiarCertificado=false,int Version=0,int VersionConfiguracion=0);
public sealed record ZeusConnectionInfo(string Servidor,string BaseDatos,string UsuarioSql,string UsuarioContable,
    bool TienePassword,bool ConfiarCertificado,int Version,int VersionConfiguracion,string Origen);

public sealed class ZeusConnectionStore(TenantConnectionFactory connections,IConfiguration configuration,IDataProtectionProvider protection)
{
    private IDataProtector Protector(long company)=>protection.CreateProtector("Zeus.Password.v1",company.ToString(System.Globalization.CultureInfo.InvariantCulture));
    public string Protect(long company,string password)=>Protector(company).Protect(password);
    public string Unprotect(long company,string encrypted)
    {
        try{return Protector(company).Unprotect(encrypted);}
        catch(CryptographicException){throw new ArgumentException("No se puede descifrar la conexión Zeus. Restaura las claves del backend o vuelve a guardar la contraseña en Empresas.");}
    }
    private SqlConnectionStringBuilder? Legacy(long company)
    {
        var text=configuration[$"Zeus:Companies:{company}:ConnectionString"];
        if(string.IsNullOrWhiteSpace(text))return null;
        try{return new(text);}catch(ArgumentException){throw new ArgumentException("La conexión privada heredada de Zeus tiene un formato inválido.");}
    }
    public static void Validate(ZeusConnectionInput input)
    {
        static void Text(string? s,int max){if(string.IsNullOrWhiteSpace(s)||s.Length>max||s.Any(char.IsControl))throw new ArgumentException("Completa servidor, base, usuario SQL y usuario contable de Zeus con valores válidos.");}
        Text(input.Servidor,150);Text(input.BaseDatos,128);Text(input.UsuarioSql,128);Text(input.UsuarioContable,20);
        if(input.Password?.Length>1024||input.Version<0||input.VersionConfiguracion<0)throw new ArgumentException("Datos de conexión Zeus inválidos.");
    }
    private static SqlConnectionStringBuilder Builder(string server,string database,string user,string password,bool trust)=>new()
    {DataSource=server,InitialCatalog=database,UserID=user,Password=password,Encrypt=true,TrustServerCertificate=trust,ConnectTimeout=15,Enlist=false,ApplicationName="NexoERP.Zeus",PersistSecurityInfo=false};
    public async Task<string?> ResolveAsync(long company,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"SELECT Servidor,BaseDatos,UsuarioSql,PasswordProtegido,ConfiarCertificado FROM core.ZeusConexion WHERE EmpresaId=@E",company);
        await using var r=await q.ExecuteReaderAsync(ct);
        if(await r.ReadAsync(ct))return Builder(r.GetString(0),r.GetString(1),r.GetString(2),Unprotect(company,r.GetString(3)),r.GetBoolean(4)).ConnectionString;
        return Legacy(company)?.ConnectionString;
    }
    public async Task<ZeusConnectionInfo> GetAsync(long company,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"""
            SELECT z.Servidor,z.BaseDatos,z.UsuarioSql,z.ConfiarCertificado,z.Version,
              ISNULL(s.Version,0),JSON_VALUE(s.Configuracion,'$.UsuarioZeus')
            FROM core.Empresa e LEFT JOIN core.ZeusConexion z ON z.EmpresaId=e.EmpresaId
            LEFT JOIN core.ZeusConfiguracion s ON s.EmpresaId=e.EmpresaId WHERE e.EmpresaId=@E
            """,company);
        await using var r=await q.ExecuteReaderAsync(ct);
        if(!await r.ReadAsync(ct))throw new ArgumentException("La empresa no existe.");
        var accounting=r.IsDBNull(6)?"":r.GetString(6);var configVersion=r.GetInt32(5);
        if(!r.IsDBNull(0))return new(r.GetString(0),r.GetString(1),r.GetString(2),accounting,true,r.GetBoolean(3),r.GetInt32(4),configVersion,"MAESTRO");
        var legacy=Legacy(company);
        return new(legacy?.DataSource??"",legacy?.InitialCatalog??"",legacy?.UserID??"",accounting,!string.IsNullOrEmpty(legacy?.Password),legacy?.TrustServerCertificate??false,0,configVersion,legacy is null?"SIN_CONFIGURAR":"SERVIDOR");
    }
    public async Task SaveAsync(SqlConnection c,SqlTransaction tx,long company,long actor,ZeusConnectionInput input,CancellationToken ct)
    {
        Validate(input);
        await using var q=ZeusRepository.Command(c,"SELECT Version,Configuracion FROM core.ZeusConfiguracion WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E",company,tx);
        ZeusSettings? settings=null;int configVersion=0;
        await using(var r=await q.ExecuteReaderAsync(ct)){if(await r.ReadAsync(ct)){configVersion=r.GetInt32(0);settings=JsonSerializer.Deserialize<ZeusSettings>(r.GetString(1));}}
        if(configVersion!=input.VersionConfiguracion)throw new ArgumentException("La configuración Zeus cambió. Cierra y vuelve a editar la empresa.");
        q.CommandText="SELECT Servidor,BaseDatos,UsuarioSql,PasswordProtegido,Version FROM core.ZeusConexion WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E";
        string? encrypted=null;string? oldServer=null,oldDatabase=null,oldUser=null;int version=0;
        await using(var r=await q.ExecuteReaderAsync(ct)){if(await r.ReadAsync(ct)){oldServer=r.GetString(0);oldDatabase=r.GetString(1);oldUser=r.GetString(2);encrypted=r.GetString(3);version=r.GetInt32(4);}}
        if(version!=input.Version)throw new ArgumentException("La conexión Zeus cambió. Cierra y vuelve a editar la empresa.");
        var legacy=encrypted is null?Legacy(company):null;
        oldServer??=legacy?.DataSource;oldDatabase??=legacy?.InitialCatalog;oldUser??=legacy?.UserID;
        if(string.IsNullOrEmpty(input.Password))
        {
            if(!string.Equals(oldServer,input.Servidor.Trim(),StringComparison.OrdinalIgnoreCase)||!string.Equals(oldDatabase,input.BaseDatos.Trim(),StringComparison.OrdinalIgnoreCase)||!string.Equals(oldUser,input.UsuarioSql.Trim(),StringComparison.Ordinal))
                throw new ArgumentException("Escribe la contraseña al cambiar servidor, base o usuario SQL.");
            if(encrypted is null){if(string.IsNullOrEmpty(legacy?.Password))throw new ArgumentException("Escribe la contraseña SQL de Zeus.");encrypted=Protect(company,legacy.Password);}
        }
        else encrypted=Protect(company,input.Password);
        q.CommandText="""
            IF EXISTS(SELECT 1 FROM core.ZeusEnvio WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND Estado IN('PENDIENTE','ENVIANDO','INCIERTO'))
              OR EXISTS(SELECT 1 FROM cxp.Egreso WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND ZeusEstado IN('PENDIENTE','ENVIANDO','INCIERTO'))
              OR EXISTS(SELECT 1 FROM core.ZeusProveedorEnvio WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND Estado IN('EN_COLA','ENVIANDO','INCIERTO'))
              THROW 52041,'Resuelve los envios Zeus pendientes o inciertos antes de cambiar la conexion.',1;
            """;
        await q.ExecuteNonQueryAsync(ct);
        settings??=new(false,"","","","","","","",[],[]);
        var destinationChanged=settings.ServidorEsperado!=input.Servidor.Trim()||settings.BaseEsperada!=input.BaseDatos.Trim();
        settings=settings with{ServidorEsperado=input.Servidor.Trim(),BaseEsperada=input.BaseDatos.Trim(),UsuarioZeus=input.UsuarioContable.Trim(),Habilitado=destinationChanged?false:settings.Habilitado};
        q.CommandText="""
            IF EXISTS(SELECT 1 FROM core.ZeusConexion WHERE EmpresaId=@E)
              UPDATE core.ZeusConexion SET Servidor=@S,BaseDatos=@B,UsuarioSql=@L,PasswordProtegido=@P,ConfiarCertificado=@T,Version=Version+1,ActualizadoPor=@U,ActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E;
            ELSE INSERT core.ZeusConexion(EmpresaId,Servidor,BaseDatos,UsuarioSql,PasswordProtegido,ConfiarCertificado,ActualizadoPor) VALUES(@E,@S,@B,@L,@P,@T,@U);
            IF EXISTS(SELECT 1 FROM core.ZeusConfiguracion WHERE EmpresaId=@E)
              UPDATE core.ZeusConfiguracion SET Configuracion=@J,Version=Version+1,ActualizadoPor=@U,ActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E;
            ELSE INSERT core.ZeusConfiguracion(EmpresaId,Configuracion,ActualizadoPor) VALUES(@E,@J,@U);
            INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,AplicacionOrigen)
              VALUES(@E,@U,'ZEUS_CONEXION_GUARDADA','core.ZeusConexion',CONVERT(nvarchar(100),@E),'SEGURIDAD');
            """;
        q.Parameters.AddWithValue("@S",input.Servidor.Trim());q.Parameters.AddWithValue("@B",input.BaseDatos.Trim());q.Parameters.AddWithValue("@L",input.UsuarioSql.Trim());
        q.Parameters.AddWithValue("@P",encrypted!);q.Parameters.AddWithValue("@T",input.ConfiarCertificado);q.Parameters.AddWithValue("@U",actor);q.Parameters.AddWithValue("@J",JsonSerializer.Serialize(settings));
        await q.ExecuteNonQueryAsync(ct);
    }
    // Solo lectura. No ejecuta procedimientos de contabilización ni crea terceros.
    public async Task<object> TestAsync(long company,ZeusConnectionInput input,CancellationToken ct)
    {
        Validate(input);var password=input.Password;
        if(string.IsNullOrEmpty(password))
        {
            var saved=await ResolveAsync(company,ct);
            if(saved is null)throw new ArgumentException("Escribe la contraseña para probar la conexión.");
            var b=new SqlConnectionStringBuilder(saved);
            if(b.DataSource!=input.Servidor.Trim()||b.InitialCatalog!=input.BaseDatos.Trim()||b.UserID!=input.UsuarioSql.Trim())throw new ArgumentException("Escribe la contraseña para probar el nuevo destino.");
            password=b.Password;
        }
        await using var c=new SqlConnection(Builder(input.Servidor.Trim(),input.BaseDatos.Trim(),input.UsuarioSql.Trim(),password,input.ConfiarCertificado).ConnectionString);
        await c.OpenAsync(ct);await using var q=c.CreateCommand();q.CommandTimeout=15;
        q.CommandText="SELECT DB_NAME(),IIF(OBJECT_ID('dbo.spWSG_Contabilidad','P') IS NOT NULL AND OBJECT_ID('dbo.DOCUMENT','U') IS NOT NULL AND OBJECT_ID('dbo.TRANSAC','U') IS NOT NULL,1,0)";
        await using var r=await q.ExecuteReaderAsync(ct);await r.ReadAsync(ct);
        return new{conectado=true,baseDatos=r.GetString(0),contratoDisponible=r.GetInt32(1)==1};
    }
}
