using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;

namespace NexoERP.Api.Security;

public sealed record CompanyMasterRow(long Id,string Codigo,string Nit,string? DigitoVerificacion,string RazonSocial,string MonedaFuncional,string ZonaHoraria,string MarcoContable,bool Activa,string Version);
public sealed record EditCompanyRequest(string Codigo,string Nit,string? DigitoVerificacion,string RazonSocial,string Version);
public sealed class CompanyMasterRepository(TenantConnectionFactory connections,AuthRepository auth)
{
    public static void Validate(string? code,string? nit,string? dv,string? name)
    {
        if(string.IsNullOrWhiteSpace(code)||code.Trim().Length>20||code.Any(char.IsControl)||string.IsNullOrWhiteSpace(nit)||nit.Trim().Length>20||nit.Any(char.IsControl)||string.IsNullOrWhiteSpace(name)||name.Trim().Length>200||name.Any(char.IsControl))
            throw new ArgumentException("Código, NIT y razón social son obligatorios (máximo 20, 20 y 200 caracteres).");
        if(!string.IsNullOrWhiteSpace(dv)&&(dv.Trim().Length!=1||!char.IsAsciiDigit(dv.Trim()[0])))throw new ArgumentException("El dígito de verificación debe ser un solo número.");
    }
    public async Task<List<CompanyMasterRow>> ListAsync(long actor,CancellationToken ct)
    {
        if(!await auth.IsSuperAdministratorAsync(actor,ct))throw new UnauthorizedAccessException();
        await using var c=await connections.OpenAsync(null,true,ct);await using var q=c.CreateCommand();
        q.CommandText="SELECT EmpresaId,Codigo,Nit,DigitoVerificacion,RazonSocial,MonedaFuncional,ZonaHoraria,MarcoContable,Activa,RowVersion FROM core.Empresa ORDER BY RazonSocial";
        await using var r=await q.ExecuteReaderAsync(ct);var rows=new List<CompanyMasterRow>();
        while(await r.ReadAsync(ct))rows.Add(new(r.GetInt64(0),r.GetString(1),r.GetString(2),r.IsDBNull(3)?null:r.GetString(3),r.GetString(4),r.GetString(5),r.GetString(6),r.GetString(7),r.GetBoolean(8),Convert.ToBase64String((byte[])r[9])));
        return rows;
    }
    public async Task UpdateAsync(long actor,long id,EditCompanyRequest input,CancellationToken ct)
    {
        if(!await auth.IsSuperAdministratorAsync(actor,ct))throw new UnauthorizedAccessException();
        Validate(input.Codigo,input.Nit,input.DigitoVerificacion,input.RazonSocial);
        byte[] version;
        try{version=Convert.FromBase64String(input.Version??"");}catch(FormatException){throw new ArgumentException("Versión de empresa inválida. Actualiza el listado.");}
        if(version.Length!=8)throw new ArgumentException("Actualiza el listado antes de editar la empresa.");
        await using var c=await connections.OpenAsync(null,true,ct);await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);await using var q=c.CreateCommand();q.Transaction=tx;
        q.CommandText="""
            IF NOT EXISTS(SELECT 1 FROM core.Empresa WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@Id AND RowVersion=@Version)
                THROW 52040,'La empresa cambio o no existe. Actualiza el listado antes de guardar.',1;
            DECLARE @Antes nvarchar(max)=(SELECT Codigo,Nit,DigitoVerificacion,RazonSocial FROM core.Empresa WHERE EmpresaId=@Id FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
            UPDATE core.Empresa SET Codigo=@Codigo,Nit=@Nit,DigitoVerificacion=@Dv,RazonSocial=@Nombre WHERE EmpresaId=@Id;
            INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
            VALUES(@Id,@Actor,'EMPRESA_ACTUALIZADA','core.Empresa',CONVERT(nvarchar(100),@Id),(SELECT JSON_QUERY(@Antes) anterior,JSON_QUERY(@Json) nuevo FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),'SEGURIDAD');
            """;
        q.Parameters.AddWithValue("@Id",id);q.Parameters.AddWithValue("@Actor",actor);q.Parameters.Add("@Version",SqlDbType.Binary,8).Value=version;
        q.Parameters.AddWithValue("@Codigo",input.Codigo.Trim().ToUpperInvariant());q.Parameters.AddWithValue("@Nit",input.Nit.Trim());q.Parameters.AddWithValue("@Nombre",input.RazonSocial.Trim());
        q.Parameters.Add("@Dv",SqlDbType.Char,1).Value=string.IsNullOrWhiteSpace(input.DigitoVerificacion)?DBNull.Value:input.DigitoVerificacion.Trim();
        q.Parameters.AddWithValue("@Json",JsonSerializer.Serialize(input));await q.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);
    }
}
public static class CompanyMasterModule
{
    public static void MapCompanyMaster(this WebApplication app)
    {
        var group=app.MapGroup("/api/v1/admin/companies");
        group.AddEndpointFilter(async(context,next)=>{
            try{return await next(context);}
            catch(UnauthorizedAccessException){return Results.Forbid();}
            catch(ArgumentException e){return Results.BadRequest(new{error=e.Message});}
            catch(SqlException e) when(e.Number==52040){return Results.Conflict(new{error=e.Message});}
            catch(SqlException e) when(e.Number is 2601 or 2627){return Results.Conflict(new{error="Ya existe una empresa con ese código."});}
        });
        group.MapGet("",async(HttpContext http,TenantConnectionFactory c,AuthRepository auth,CancellationToken ct)=>Results.Ok(await new CompanyMasterRepository(c,auth).ListAsync(Convert.ToInt64(http.Items["UsuarioId"]),ct))).RequireSuperAdministrator();
        group.MapPut("/{id:long}",async(long id,EditCompanyRequest input,HttpContext http,TenantConnectionFactory c,AuthRepository auth,CancellationToken ct)=>{await new CompanyMasterRepository(c,auth).UpdateAsync(Convert.ToInt64(http.Items["UsuarioId"]),id,input,ct);return Results.NoContent();}).RequireSuperAdministrator();
    }
}
