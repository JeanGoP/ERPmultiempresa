using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
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
        bool superAdministrator;
        await using(var query=connection.CreateCommand())
        {
            query.CommandText="""
                SELECT u.UsuarioId,u.NombreCompleto,c.PasswordHash,c.PasswordSalt,c.Iteraciones,c.BloqueadoHastaUtc,u.EsSuperAdministrador
                FROM seg.Usuario u JOIN seg.UsuarioCredencial c ON c.UsuarioId=u.UsuarioId
                WHERE u.Correo=@Correo AND u.Activo=1;
                """;
            query.Parameters.Add(new SqlParameter("@Correo",SqlDbType.NVarChar,254){Value=input.Correo.Trim()});
            await using var reader=await query.ExecuteReaderAsync(cancellationToken);
            if(!await reader.ReadAsync(cancellationToken)) return null;
            userId=reader.GetInt64(0); name=reader.GetString(1); expected=(byte[])reader[2]; salt=(byte[])reader[3]; iterations=reader.GetInt32(4); blocked=reader.IsDBNull(5)?null:reader.GetDateTime(5); superAdministrator=reader.GetBoolean(6);
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
        return new(ToBase64Url(rawToken),expires,userId,name,superAdministrator);
    }

    public async Task<AuthenticatedUser?> ValidateAsync(string token,CancellationToken cancellationToken)
    {
        byte[] raw;
        try { raw=FromBase64Url(token); } catch(FormatException) { return null; }
        if(raw.Length!=32) return null;
        await using var connection=await connections.OpenAsync(null,true,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT u.UsuarioId,u.Correo,u.NombreCompleto,u.EsSuperAdministrador
            FROM seg.SesionApi s JOIN seg.Usuario u ON u.UsuarioId=s.UsuarioId
            WHERE s.TokenHash=@TokenHash AND s.RevocadaEnUtc IS NULL AND s.ExpiraEnUtc>SYSUTCDATETIME() AND u.Activo=1;
            """;
        command.Parameters.Add(new SqlParameter("@TokenHash",SqlDbType.Binary,32){Value=SHA256.HashData(raw)});
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken)?new(reader.GetInt64(0),reader.GetString(1),reader.GetString(2),reader.GetBoolean(3)):null;
    }

    public async Task<bool> HasCompanyAccessAsync(long userId,long empresaId,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(null,true,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandText="SELECT IIF(EXISTS(SELECT 1 FROM seg.Usuario WHERE UsuarioId=@UsuarioId AND Activo=1 AND EsSuperAdministrador=1) OR EXISTS(SELECT 1 FROM seg.UsuarioEmpresaRol WHERE UsuarioId=@UsuarioId AND EmpresaId=@EmpresaId AND Activo=1),1,0);";
        command.Parameters.Add(new SqlParameter("@UsuarioId",SqlDbType.BigInt){Value=userId});
        command.Parameters.Add(new SqlParameter("@EmpresaId",SqlDbType.BigInt){Value=empresaId});
        return Convert.ToBoolean(await command.ExecuteScalarAsync(cancellationToken));
    }

    public async Task<IReadOnlyList<CompanyAccessResponse>> GetCompaniesAsync(long userId,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(null,true,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT e.EmpresaId,e.Codigo,e.Nit,e.RazonSocial,e.MonedaFuncional
            FROM core.Empresa e
            WHERE e.Activa=1 AND
            (
                EXISTS(SELECT 1 FROM seg.Usuario WHERE UsuarioId=@UsuarioId AND Activo=1 AND EsSuperAdministrador=1)
                OR EXISTS(SELECT 1 FROM seg.UsuarioEmpresaRol ur WHERE ur.EmpresaId=e.EmpresaId AND ur.UsuarioId=@UsuarioId AND ur.Activo=1)
            )
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
        if(await IsSuperAdministratorAsync(userId,cancellationToken)) return true;
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

    public async Task<bool> IsSuperAdministratorAsync(long userId,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(null,true,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandText="SELECT IIF(EXISTS(SELECT 1 FROM seg.Usuario WHERE UsuarioId=@UsuarioId AND Activo=1 AND EsSuperAdministrador=1),1,0);";
        command.Parameters.Add(new SqlParameter("@UsuarioId",SqlDbType.BigInt){Value=userId});
        return Convert.ToBoolean(await command.ExecuteScalarAsync(cancellationToken));
    }

    public async Task<CompanyAccessResponse> CreateCompanyAsync(long userId,CreateCompanyRequest input,CancellationToken cancellationToken)
    {
        if(!await IsSuperAdministratorAsync(userId,cancellationToken)) throw new UnauthorizedAccessException("Se requiere un superadministrador global.");
        var code=input.Codigo.Trim().ToUpperInvariant();
        var nit=input.Nit.Trim();
        var name=input.RazonSocial.Trim();
        var currency=string.IsNullOrWhiteSpace(input.MonedaFuncional)?"COP":input.MonedaFuncional.Trim().ToUpperInvariant();
        var timezone=string.IsNullOrWhiteSpace(input.ZonaHoraria)?"America/Bogota":input.ZonaHoraria.Trim();
        var framework=string.IsNullOrWhiteSpace(input.MarcoContable)?"GRUPO_2":input.MarcoContable.Trim().ToUpperInvariant();
        if(currency.Length!=3) throw new ArgumentException("La moneda funcional debe tener tres caracteres.");
        if(framework is not ("GRUPO_1" or "GRUPO_2" or "GRUPO_3")) throw new ArgumentException("El marco contable no es válido.");

        await using var connection=await connections.OpenAsync(null,true,cancellationToken);
        await using var transaction=await connection.BeginTransactionAsync(cancellationToken);
        long companyId;
        await using(var command=connection.CreateCommand())
        {
            command.Transaction=(SqlTransaction)transaction;
            command.CommandText="""
                INSERT core.Empresa(Codigo,Nit,DigitoVerificacion,RazonSocial,MonedaFuncional,ZonaHoraria,MarcoContable)
                OUTPUT inserted.EmpresaId
                VALUES(@Codigo,@Nit,@Dv,@Nombre,@Moneda,@Zona,@Marco);
                """;
            command.Parameters.Add(new SqlParameter("@Codigo",SqlDbType.NVarChar,20){Value=code});
            command.Parameters.Add(new SqlParameter("@Nit",SqlDbType.NVarChar,20){Value=nit});
            command.Parameters.Add(new SqlParameter("@Dv",SqlDbType.Char,1){Value=string.IsNullOrWhiteSpace(input.DigitoVerificacion)?DBNull.Value:input.DigitoVerificacion.Trim()[..1]});
            command.Parameters.Add(new SqlParameter("@Nombre",SqlDbType.NVarChar,200){Value=name});
            command.Parameters.Add(new SqlParameter("@Moneda",SqlDbType.Char,3){Value=currency});
            command.Parameters.Add(new SqlParameter("@Zona",SqlDbType.NVarChar,80){Value=timezone});
            command.Parameters.Add(new SqlParameter("@Marco",SqlDbType.VarChar,20){Value=framework});
            companyId=Convert.ToInt64(await command.ExecuteScalarAsync(cancellationToken));
        }
        await using(var configuration=connection.CreateCommand())
        {
            configuration.Transaction=(SqlTransaction)transaction;
            configuration.CommandText="INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);";
            configuration.Parameters.Add(new SqlParameter("@EmpresaId",SqlDbType.BigInt){Value=companyId});
            await configuration.ExecuteNonQueryAsync(cancellationToken);
        }
        await using(var audit=connection.CreateCommand())
        {
            audit.Transaction=(SqlTransaction)transaction;
            audit.CommandText="INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@EmpresaId,@UsuarioId,'EMPRESA_CREADA','core.Empresa',CONVERT(nvarchar(100),@EmpresaId),@Valores,'NexoERP.Api');";
            audit.Parameters.Add(new SqlParameter("@EmpresaId",SqlDbType.BigInt){Value=companyId});
            audit.Parameters.Add(new SqlParameter("@UsuarioId",SqlDbType.BigInt){Value=userId});
            audit.Parameters.Add(new SqlParameter("@Valores",SqlDbType.NVarChar,-1){Value=JsonSerializer.Serialize(new { codigo=code,nit,razonSocial=name,monedaFuncional=currency,zonaHoraria=timezone,marcoContable=framework })});
            await audit.ExecuteNonQueryAsync(cancellationToken);
        }
        await transaction.CommitAsync(cancellationToken);
        return new(companyId,code,nit,name,currency);
    }

    private static string ToBase64Url(byte[] value)=>Convert.ToBase64String(value).TrimEnd('=').Replace('+','-').Replace('/','_');
    private static byte[] FromBase64Url(string value)
    {
        var normalized=value.Replace('-','+').Replace('_','/');
        normalized+=new string('=',(4-normalized.Length%4)%4);
        return Convert.FromBase64String(normalized);
    }
}
