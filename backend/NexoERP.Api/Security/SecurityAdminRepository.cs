using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;

namespace NexoERP.Api.Security;

public sealed class SecurityAdminRepository(TenantConnectionFactory connections)
{
    private const int PasswordIterations=210000;

    public async Task<IReadOnlyList<SecurityUserResponse>> GetUsersAsync(long empresaId,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,ct);
        var users=new Dictionary<long,(string Email,string Name,bool Global,bool Access,List<SecurityRoleSummary> Roles)>();
        await using(var command=connection.CreateCommand())
        {
            command.CommandText="""
                SELECT u.UsuarioId,u.Correo,u.NombreCompleto,u.Activo,
                       CONVERT(bit,MAX(CONVERT(int,ur.Activo))) AccesoActivo
                FROM seg.UsuarioEmpresaRol ur
                JOIN seg.Usuario u ON u.UsuarioId=ur.UsuarioId
                WHERE ur.EmpresaId=@EmpresaId
                GROUP BY u.UsuarioId,u.Correo,u.NombreCompleto,u.Activo
                ORDER BY u.NombreCompleto,u.Correo;
                """;
            Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);
            await using var reader=await command.ExecuteReaderAsync(ct);
            while(await reader.ReadAsync(ct)) users[reader.GetInt64(0)]=(reader.GetString(1),reader.GetString(2),reader.GetBoolean(3),reader.GetBoolean(4),[]);
        }
        await using(var command=connection.CreateCommand())
        {
            command.CommandText="""
                SELECT ur.UsuarioId,r.RolId,r.Codigo,r.Nombre
                FROM seg.UsuarioEmpresaRol ur JOIN seg.Rol r ON r.RolId=ur.RolId
                WHERE ur.EmpresaId=@EmpresaId
                ORDER BY r.Nombre;
                """;
            Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);
            await using var reader=await command.ExecuteReaderAsync(ct);
            while(await reader.ReadAsync(ct)) if(users.TryGetValue(reader.GetInt64(0),out var user)) user.Roles.Add(new(reader.GetInt64(1),reader.GetString(2),reader.GetString(3)));
        }
        return users.Select(x=>new SecurityUserResponse(x.Key,x.Value.Email,x.Value.Name,x.Value.Global,x.Value.Access,x.Value.Roles)).ToList();
    }

    public async Task<IReadOnlyList<SecurityPermissionResponse>> GetPermissionsCatalogAsync(CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(null,true,ct);
        await using var command=connection.CreateCommand();
        command.CommandText="SELECT PermisoId,Codigo,Modulo,Accion,Nombre,EsCritico FROM seg.Permiso WHERE Activo=1 ORDER BY Modulo,Nombre;";
        await using var reader=await command.ExecuteReaderAsync(ct);
        var result=new List<SecurityPermissionResponse>();
        while(await reader.ReadAsync(ct)) result.Add(new(reader.GetInt64(0),reader.GetString(1),reader.GetString(2),reader.GetString(3),reader.GetString(4),reader.GetBoolean(5)));
        return result;
    }

    public async Task<IReadOnlyList<SecurityRoleResponse>> GetRolesAsync(CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(null,true,ct);
        var roles=new Dictionary<long,(string Code,string Name,List<long> Permissions)>();
        await using(var command=connection.CreateCommand())
        {
            command.CommandText="SELECT RolId,Codigo,Nombre FROM seg.Rol ORDER BY Nombre;";
            await using var reader=await command.ExecuteReaderAsync(ct);
            while(await reader.ReadAsync(ct)) roles[reader.GetInt64(0)]=(reader.GetString(1),reader.GetString(2),[]);
        }
        await using(var command=connection.CreateCommand())
        {
            command.CommandText="SELECT RolId,PermisoId FROM seg.RolPermiso ORDER BY RolId,PermisoId;";
            await using var reader=await command.ExecuteReaderAsync(ct);
            while(await reader.ReadAsync(ct)) if(roles.TryGetValue(reader.GetInt64(0),out var role)) role.Permissions.Add(reader.GetInt64(1));
        }
        return roles.Select(x=>new SecurityRoleResponse(x.Key,x.Value.Code,x.Value.Name,x.Value.Permissions)).ToList();
    }

    public async Task<(SecurityUserResponse User,bool UsuarioExistente)> CreateUserAsync(long empresaId,long actorId,CreateSecurityUserRequest input,CancellationToken ct)
    {
        var email=input.Correo.Trim().ToLowerInvariant();
        var name=input.NombreCompleto.Trim();
        var roleIds=input.RolIds.Distinct().ToArray();
        await using var connection=await connections.OpenAsync(empresaId,false,ct);
        await using var transaction=(SqlTransaction)await connection.BeginTransactionAsync(ct);
        await EnsureRolesAsync(connection,transaction,roleIds,ct);
        long userId;
        var existing=false;
        await using(var query=connection.CreateCommand())
        {
            query.Transaction=transaction;
            query.CommandText="SELECT UsuarioId FROM seg.Usuario WITH(UPDLOCK,HOLDLOCK) WHERE Correo=@Correo;";
            Add(query,"@Correo",SqlDbType.NVarChar,email,254);
            var value=await query.ExecuteScalarAsync(ct);
            existing=value is not null;
            if(existing) userId=Convert.ToInt64(value);
            else
            {
                query.Parameters.Clear();
                query.CommandText="INSERT seg.Usuario(Correo,NombreCompleto,Activo) VALUES(@Correo,@Nombre,1); SELECT CONVERT(bigint,SCOPE_IDENTITY());";
                Add(query,"@Correo",SqlDbType.NVarChar,email,254);Add(query,"@Nombre",SqlDbType.NVarChar,name,150);
                userId=Convert.ToInt64(await query.ExecuteScalarAsync(ct));
                await SavePasswordAsync(connection,transaction,userId,input.Password,ct);
            }
        }
        if(existing)
        {
            await using var duplicate=connection.CreateCommand();duplicate.Transaction=transaction;
            duplicate.CommandText="SELECT COUNT(*) FROM seg.UsuarioEmpresaRol WHERE EmpresaId=@EmpresaId AND UsuarioId=@UsuarioId;";
            Add(duplicate,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(duplicate,"@UsuarioId",SqlDbType.BigInt,userId);
            if(Convert.ToInt32(await duplicate.ExecuteScalarAsync(ct))>0) throw new InvalidOperationException("El usuario ya está vinculado a esta empresa.");
        }
        await SaveUserRolesAsync(connection,transaction,empresaId,userId,roleIds,input.AccesoActivo,ct);
        await AuditAsync(connection,transaction,empresaId,actorId,"USUARIO_EMPRESA_CREADO","seg.UsuarioEmpresaRol",userId,new { email,roles=roleIds,accesoActivo=input.AccesoActivo,usuarioExistente=existing },ct);
        await transaction.CommitAsync(ct);
        var user=(await GetUsersAsync(empresaId,ct)).Single(x=>x.UsuarioId==userId);
        return (user,existing);
    }

    public async Task<SecurityUserResponse> UpdateUserAsync(long empresaId,long userId,long actorId,UpdateSecurityUserRequest input,CancellationToken ct)
    {
        if(userId==actorId&&!input.AccesoActivo) throw new InvalidOperationException("No puedes desactivar tu propio acceso a la empresa.");
        var roleIds=input.RolIds.Distinct().ToArray();
        await using var connection=await connections.OpenAsync(empresaId,false,ct);
        await using var transaction=(SqlTransaction)await connection.BeginTransactionAsync(ct);
        await EnsureCompanyUserAsync(connection,transaction,empresaId,userId,ct);
        await EnsureRolesAsync(connection,transaction,roleIds,ct);
        await SaveUserRolesAsync(connection,transaction,empresaId,userId,roleIds,input.AccesoActivo,ct);
        await AuditAsync(connection,transaction,empresaId,actorId,"USUARIO_EMPRESA_ACTUALIZADO","seg.UsuarioEmpresaRol",userId,new { roles=roleIds,accesoActivo=input.AccesoActivo },ct);
        await transaction.CommitAsync(ct);
        return (await GetUsersAsync(empresaId,ct)).Single(x=>x.UsuarioId==userId);
    }

    public async Task ResetPasswordAsync(long empresaId,long userId,long actorId,bool actorIsSuperAdministrator,string password,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,ct);
        await using var transaction=(SqlTransaction)await connection.BeginTransactionAsync(ct);
        await EnsureCompanyUserAsync(connection,transaction,empresaId,userId,ct);
        if(!actorIsSuperAdministrator)
        {
            await using var count=connection.CreateCommand();count.Transaction=transaction;
            count.CommandText="SELECT COUNT(DISTINCT EmpresaId) FROM seg.UsuarioEmpresaRol WHERE UsuarioId=@UsuarioId AND Activo=1;";
            Add(count,"@UsuarioId",SqlDbType.BigInt,userId);
            if(Convert.ToInt32(await count.ExecuteScalarAsync(ct))>1) throw new InvalidOperationException("Un usuario multiempresa solo puede cambiarse desde el superadministrador.");
        }
        await SavePasswordAsync(connection,transaction,userId,password,ct);
        await using(var revoke=connection.CreateCommand())
        {
            revoke.Transaction=transaction;revoke.CommandText="UPDATE seg.SesionApi SET RevocadaEnUtc=COALESCE(RevocadaEnUtc,SYSUTCDATETIME()) WHERE UsuarioId=@UsuarioId;";
            Add(revoke,"@UsuarioId",SqlDbType.BigInt,userId);await revoke.ExecuteNonQueryAsync(ct);
        }
        await AuditAsync(connection,transaction,empresaId,actorId,"PASSWORD_USUARIO_RESTABLECIDO","seg.UsuarioCredencial",userId,new { sesionesRevocadas=true },ct);
        await transaction.CommitAsync(ct);
    }

    public async Task<SecurityRoleResponse> SaveRoleAsync(long empresaId,long? roleId,long actorId,SaveSecurityRoleRequest input,CancellationToken ct)
    {
        var code=input.Codigo.Trim().ToUpperInvariant();var name=input.Nombre.Trim();var permissionIds=input.PermisoIds.Distinct().ToArray();
        await using var connection=await connections.OpenAsync(null,true,ct);
        await using var transaction=(SqlTransaction)await connection.BeginTransactionAsync(ct);
        await EnsurePermissionsAsync(connection,transaction,permissionIds,ct);
        long id;
        await using(var command=connection.CreateCommand())
        {
            command.Transaction=transaction;
            if(roleId is null)
            {
                command.CommandText="INSERT seg.Rol(Codigo,Nombre) VALUES(@Codigo,@Nombre); SELECT CONVERT(bigint,SCOPE_IDENTITY());";
                Add(command,"@Codigo",SqlDbType.VarChar,code,50);Add(command,"@Nombre",SqlDbType.NVarChar,name,100);id=Convert.ToInt64(await command.ExecuteScalarAsync(ct));
            }
            else
            {
                command.CommandText="UPDATE seg.Rol SET Codigo=@Codigo,Nombre=@Nombre WHERE RolId=@RolId; IF @@ROWCOUNT=0 THROW 51030,'El rol no existe.',1;";
                Add(command,"@Codigo",SqlDbType.VarChar,code,50);Add(command,"@Nombre",SqlDbType.NVarChar,name,100);Add(command,"@RolId",SqlDbType.BigInt,roleId.Value);await command.ExecuteNonQueryAsync(ct);id=roleId.Value;
            }
        }
        await using(var permissions=connection.CreateCommand())
        {
            permissions.Transaction=transaction;permissions.CommandText="DELETE seg.RolPermiso WHERE RolId=@RolId;";Add(permissions,"@RolId",SqlDbType.BigInt,id);await permissions.ExecuteNonQueryAsync(ct);
            foreach(var permissionId in permissionIds){permissions.Parameters.Clear();permissions.CommandText="INSERT seg.RolPermiso(RolId,PermisoId) VALUES(@RolId,@PermisoId);";Add(permissions,"@RolId",SqlDbType.BigInt,id);Add(permissions,"@PermisoId",SqlDbType.BigInt,permissionId);await permissions.ExecuteNonQueryAsync(ct);}
        }
        await AuditAsync(connection,transaction,empresaId,actorId,roleId is null?"ROL_CREADO":"ROL_ACTUALIZADO","seg.Rol",id,new { codigo=code,nombre=name,permisos=permissionIds },ct);
        await transaction.CommitAsync(ct);
        return (await GetRolesAsync(ct)).Single(x=>x.RolId==id);
    }

    private static async Task SaveUserRolesAsync(SqlConnection connection,SqlTransaction transaction,long empresaId,long userId,IReadOnlyCollection<long> roleIds,bool active,CancellationToken ct)
    {
        await using(var clear=connection.CreateCommand())
        {
            clear.Transaction=transaction;clear.CommandText="DELETE seg.UsuarioEmpresaRol WHERE EmpresaId=@EmpresaId AND UsuarioId=@UsuarioId;";
            Add(clear,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(clear,"@UsuarioId",SqlDbType.BigInt,userId);await clear.ExecuteNonQueryAsync(ct);
        }
        foreach(var roleId in roleIds)
        {
            await using var command=connection.CreateCommand();command.Transaction=transaction;
            command.CommandText="INSERT seg.UsuarioEmpresaRol(EmpresaId,UsuarioId,RolId,Activo) VALUES(@EmpresaId,@UsuarioId,@RolId,@Activo);";
            Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(command,"@UsuarioId",SqlDbType.BigInt,userId);Add(command,"@RolId",SqlDbType.BigInt,roleId);Add(command,"@Activo",SqlDbType.Bit,active);await command.ExecuteNonQueryAsync(ct);
        }
    }

    private static async Task SavePasswordAsync(SqlConnection connection,SqlTransaction transaction,long userId,string password,CancellationToken ct)
    {
        var salt=RandomNumberGenerator.GetBytes(32);
        var hash=Rfc2898DeriveBytes.Pbkdf2(Encoding.UTF8.GetBytes(password),salt,PasswordIterations,HashAlgorithmName.SHA512,64);
        await using var command=connection.CreateCommand();command.Transaction=transaction;
        command.CommandText="""
            MERGE seg.UsuarioCredencial AS target USING(SELECT @UsuarioId UsuarioId) source ON target.UsuarioId=source.UsuarioId
            WHEN MATCHED THEN UPDATE SET PasswordHash=@Hash,PasswordSalt=@Salt,Iteraciones=@Iteraciones,IntentosFallidos=0,BloqueadoHastaUtc=NULL,PasswordActualizadoEnUtc=SYSUTCDATETIME()
            WHEN NOT MATCHED THEN INSERT(UsuarioId,PasswordHash,PasswordSalt,Iteraciones) VALUES(@UsuarioId,@Hash,@Salt,@Iteraciones);
            """;
        Add(command,"@UsuarioId",SqlDbType.BigInt,userId);Add(command,"@Hash",SqlDbType.VarBinary,hash,64);Add(command,"@Salt",SqlDbType.VarBinary,salt,32);Add(command,"@Iteraciones",SqlDbType.Int,PasswordIterations);await command.ExecuteNonQueryAsync(ct);
    }

    private static async Task EnsureRolesAsync(SqlConnection connection,SqlTransaction transaction,IReadOnlyCollection<long> ids,CancellationToken ct)
    {
        if(ids.Count==0) throw new InvalidOperationException("Selecciona al menos un rol.");
        foreach(var id in ids){await using var command=connection.CreateCommand();command.Transaction=transaction;command.CommandText="SELECT COUNT(*) FROM seg.Rol WHERE RolId=@Id;";Add(command,"@Id",SqlDbType.BigInt,id);if(Convert.ToInt32(await command.ExecuteScalarAsync(ct))==0) throw new InvalidOperationException("Uno de los roles seleccionados no existe.");}
    }
    private static async Task EnsurePermissionsAsync(SqlConnection connection,SqlTransaction transaction,IReadOnlyCollection<long> ids,CancellationToken ct)
    {
        foreach(var id in ids){await using var command=connection.CreateCommand();command.Transaction=transaction;command.CommandText="SELECT COUNT(*) FROM seg.Permiso WHERE PermisoId=@Id AND Activo=1;";Add(command,"@Id",SqlDbType.BigInt,id);if(Convert.ToInt32(await command.ExecuteScalarAsync(ct))==0) throw new InvalidOperationException("Uno de los permisos seleccionados no existe.");}
    }
    private static async Task EnsureCompanyUserAsync(SqlConnection connection,SqlTransaction transaction,long empresaId,long userId,CancellationToken ct)
    {
        await using var command=connection.CreateCommand();command.Transaction=transaction;command.CommandText="SELECT COUNT(*) FROM seg.UsuarioEmpresaRol WHERE EmpresaId=@EmpresaId AND UsuarioId=@UsuarioId;";Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(command,"@UsuarioId",SqlDbType.BigInt,userId);if(Convert.ToInt32(await command.ExecuteScalarAsync(ct))==0) throw new InvalidOperationException("El usuario no está vinculado a esta empresa.");
    }
    private static async Task AuditAsync(SqlConnection connection,SqlTransaction transaction,long empresaId,long actorId,string operation,string entity,long entityId,object values,CancellationToken ct)
    {
        await using var command=connection.CreateCommand();command.Transaction=transaction;
        command.CommandText="INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@EmpresaId,@Actor,@Operacion,@Entidad,CONVERT(nvarchar(100),@EntidadId),@Valores,'SEGURIDAD');";
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(command,"@Actor",SqlDbType.BigInt,actorId);Add(command,"@Operacion",SqlDbType.VarChar,operation,80);Add(command,"@Entidad",SqlDbType.VarChar,entity,100);Add(command,"@EntidadId",SqlDbType.BigInt,entityId);Add(command,"@Valores",SqlDbType.NVarChar,JsonSerializer.Serialize(values),-1);await command.ExecuteNonQueryAsync(ct);
    }
    private static void Add(SqlCommand command,string name,SqlDbType type,object? value,int size=0)
    {
        var parameter=size==0?new SqlParameter(name,type):new SqlParameter(name,type,size);parameter.Value=value??DBNull.Value;command.Parameters.Add(parameter);
    }
}
