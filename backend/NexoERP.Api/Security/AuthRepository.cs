using System.Data;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;

namespace NexoERP.Api.Security;

public sealed class AuthRepository(TenantConnectionFactory connections)
{
    public async Task<LoginResponse?> LoginAsync(LoginRequest input,string? address,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(null,true,cancellationToken);
        long userId;
        string name;
        byte[] expected;
        byte[] salt;
        int iterations;
        DateTime? blocked;
        await using(var query=connection.CreateCommand())
        {
            query.CommandText="""
                SELECT u.UsuarioId,u.NombreCompleto,c.PasswordHash,c.PasswordSalt,c.Iteraciones,c.BloqueadoHastaUtc
                FROM seg.Usuario u JOIN seg.UsuarioCredencial c ON c.UsuarioId=u.UsuarioId
                WHERE u.Correo=@Correo AND u.Activo=1;
                """;
            query.Parameters.Add(new SqlParameter("@Correo",SqlDbType.NVarChar,254){Value=input.Correo.Trim()});
            await using var reader=await query.ExecuteReaderAsync(cancellationToken);
            if(!await reader.ReadAsync(cancellationToken)) return null;
            userId=reader.GetInt64(0); name=reader.GetString(1); expected=(byte[])reader[2]; salt=(byte[])reader[3]; iterations=reader.GetInt32(4); blocked=reader.IsDBNull(5)?null:reader.GetDateTime(5);
        }
        if(blocked>DateTime.UtcNow) return null;
        var actual=Rfc2898DeriveBytes.Pbkdf2(Encoding.UTF8.GetBytes(input.Password),salt,iterations,HashAlgorithmName.SHA512,64);
        if(!CryptographicOperations.FixedTimeEquals(actual,expected))
        {
            await using var failed=connection.CreateCommand();
            failed.CommandText="""
                UPDATE seg.UsuarioCredencial SET IntentosFallidos=IntentosFallidos+1,
                BloqueadoHastaUtc=CASE WHEN IntentosFallidos+1>=5 THEN DATEADD(minute,15,SYSUTCDATETIME()) ELSE BloqueadoHastaUtc END
                WHERE UsuarioId=@UsuarioId;
                """;
            failed.Parameters.Add(new SqlParameter("@UsuarioId",SqlDbType.BigInt){Value=userId});
            await failed.ExecuteNonQueryAsync(cancellationToken);
            return null;
        }
        var rawToken=RandomNumberGenerator.GetBytes(32);
        var tokenHash=SHA256.HashData(rawToken);
        var expires=DateTime.UtcNow.AddHours(8);
        await using(var success=connection.CreateCommand())
        {
            success.CommandText="""
                UPDATE seg.UsuarioCredencial SET IntentosFallidos=0,BloqueadoHastaUtc=NULL WHERE UsuarioId=@UsuarioId;
                INSERT seg.SesionApi(UsuarioId,TokenHash,ExpiraEnUtc,DireccionIp) VALUES(@UsuarioId,@TokenHash,@ExpiraEnUtc,@DireccionIp);
                """;
            success.Parameters.Add(new SqlParameter("@UsuarioId",SqlDbType.BigInt){Value=userId});
            success.Parameters.Add(new SqlParameter("@TokenHash",SqlDbType.Binary,32){Value=tokenHash});
            success.Parameters.Add(new SqlParameter("@ExpiraEnUtc",SqlDbType.DateTime2){Value=expires});
            success.Parameters.Add(new SqlParameter("@DireccionIp",SqlDbType.NVarChar,64){Value=(object?)address??DBNull.Value});
            await success.ExecuteNonQueryAsync(cancellationToken);
        }
        return new(ToBase64Url(rawToken),expires,userId,name);
    }

    public async Task<AuthenticatedUser?> ValidateAsync(string token,CancellationToken cancellationToken)
    {
        byte[] raw;
        try { raw=FromBase64Url(token); } catch(FormatException) { return null; }
        if(raw.Length!=32) return null;
        await using var connection=await connections.OpenAsync(null,true,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT u.UsuarioId,u.Correo,u.NombreCompleto
            FROM seg.SesionApi s JOIN seg.Usuario u ON u.UsuarioId=s.UsuarioId
            WHERE s.TokenHash=@TokenHash AND s.RevocadaEnUtc IS NULL AND s.ExpiraEnUtc>SYSUTCDATETIME() AND u.Activo=1;
            """;
        command.Parameters.Add(new SqlParameter("@TokenHash",SqlDbType.Binary,32){Value=SHA256.HashData(raw)});
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken)?new(reader.GetInt64(0),reader.GetString(1),reader.GetString(2)):null;
    }

    public async Task<bool> HasCompanyAccessAsync(long userId,long empresaId,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(null,true,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandText="SELECT IIF(EXISTS(SELECT 1 FROM seg.UsuarioEmpresaRol WHERE UsuarioId=@UsuarioId AND EmpresaId=@EmpresaId AND Activo=1),1,0);";
        command.Parameters.Add(new SqlParameter("@UsuarioId",SqlDbType.BigInt){Value=userId});
        command.Parameters.Add(new SqlParameter("@EmpresaId",SqlDbType.BigInt){Value=empresaId});
        return Convert.ToBoolean(await command.ExecuteScalarAsync(cancellationToken));
    }

    public async Task<IReadOnlyList<CompanyAccessResponse>> GetCompaniesAsync(long userId,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(null,true,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT DISTINCT e.EmpresaId,e.Codigo,e.Nit,e.RazonSocial,e.MonedaFuncional
            FROM seg.UsuarioEmpresaRol ur
            JOIN core.Empresa e ON e.EmpresaId=ur.EmpresaId
            WHERE ur.UsuarioId=@UsuarioId AND ur.Activo=1 AND e.Activa=1
            ORDER BY e.RazonSocial;
            """;
        command.Parameters.Add(new SqlParameter("@UsuarioId",SqlDbType.BigInt){Value=userId});
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);
        var result=new List<CompanyAccessResponse>();
        while(await reader.ReadAsync(cancellationToken)) result.Add(new(reader.GetInt64(0),reader.GetString(1),reader.GetString(2),reader.GetString(3),reader.GetString(4)));
        return result;
    }

    public async Task<bool> HasPermissionAsync(long userId,long empresaId,string permission,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandText="SELECT seg.fn_TienePermiso(@EmpresaId,@UsuarioId,@Permiso);";
        command.Parameters.Add(new SqlParameter("@EmpresaId",SqlDbType.BigInt){Value=empresaId});
        command.Parameters.Add(new SqlParameter("@UsuarioId",SqlDbType.BigInt){Value=userId});
        command.Parameters.Add(new SqlParameter("@Permiso",SqlDbType.VarChar,100){Value=permission});
        return Convert.ToBoolean(await command.ExecuteScalarAsync(cancellationToken));
    }

    public async Task<IReadOnlyList<PermissionResponse>> GetPermissionsAsync(long userId,long empresaId,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT Codigo,Modulo,Accion,Nombre,EsCritico
            FROM seg.Permiso
            WHERE Activo=1 AND seg.fn_TienePermiso(@EmpresaId,@UsuarioId,Codigo)=1
            ORDER BY Modulo,Codigo;
            """;
        command.Parameters.Add(new SqlParameter("@EmpresaId",SqlDbType.BigInt){Value=empresaId});
        command.Parameters.Add(new SqlParameter("@UsuarioId",SqlDbType.BigInt){Value=userId});
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);
        var result=new List<PermissionResponse>();
        while(await reader.ReadAsync(cancellationToken)) result.Add(new(reader.GetString(0),reader.GetString(1),reader.GetString(2),reader.GetString(3),reader.GetBoolean(4)));
        return result;
    }

    private static string ToBase64Url(byte[] value)=>Convert.ToBase64String(value).TrimEnd('=').Replace('+','-').Replace('/','_');
    private static byte[] FromBase64Url(string value)
    {
        var normalized=value.Replace('-','+').Replace('_','/');
        normalized+=new string('=',(4-normalized.Length%4)%4);
        return Convert.FromBase64String(normalized);
    }
}
