using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;
using NexoERP.Api.Security;
using NexoERP.Api.Zeus;

namespace NexoERP.Api.MasterData;

public sealed record BranchResponse(long Id,string Codigo,string Nombre,bool Activa);
public sealed record SaveBranchRequest(string Codigo,string Nombre,bool Activa);
public sealed class BranchCatalogRepository(TenantConnectionFactory connections)
{
    public async Task<List<BranchResponse>> ListAsync(long company,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"SELECT SucursalId,Codigo,Nombre,Activa FROM core.Sucursal WHERE EmpresaId=@E ORDER BY Codigo",company);
        await using var r=await q.ExecuteReaderAsync(ct);var rows=new List<BranchResponse>();
        while(await r.ReadAsync(ct))rows.Add(new(r.GetInt64(0),r.GetString(1),r.GetString(2),r.GetBoolean(3)));
        return rows;
    }
    public async Task<long> SaveAsync(long company,long? id,SaveBranchRequest input,long user,CancellationToken ct)
    {
        if(string.IsNullOrWhiteSpace(input.Codigo)||input.Codigo.Trim().Length>20||string.IsNullOrWhiteSpace(input.Nombre)||input.Nombre.Trim().Length>80||input.Codigo.Any(char.IsControl)||input.Nombre.Any(char.IsControl))
            throw new ArgumentException("Código y nombre obligatorios: máximo 20 y 80 caracteres respectivamente.");
        input=input with{Codigo=input.Codigo.Trim().ToUpperInvariant(),Nombre=input.Nombre.Trim()};
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        // Mismo orden de bloqueo que guardar configuración: configuración, luego catálogo.
        await using var q=ZeusRepository.Command(c,"SELECT Configuracion FROM core.ZeusConfiguracion WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E",company,tx);
        var json=await q.ExecuteScalarAsync(ct) as string;
        if(id is not null)
        {
            q.CommandText="SELECT Nombre FROM core.Sucursal WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND SucursalId=@Id";ZeusRepository.Add(q,"@Id",id.Value);
            var previous=await q.ExecuteScalarAsync(ct) as string??throw new ArgumentException("Sucursal no encontrada en esta empresa.");
            if(!input.Activa)
            {
                q.CommandText="SELECT COUNT(*) FROM inv.Bodega WHERE EmpresaId=@E AND SucursalId=@Id AND Activa=1";
                if(Convert.ToInt32(await q.ExecuteScalarAsync(ct))>0)throw new ArgumentException("La sucursal tiene bodegas activas asignadas. Reasígnalas antes de desactivarla.");
            }
            var routes=json is null?[]:JsonSerializer.Deserialize<ZeusSettings>(json)!.FuentesAutomaticas??[];
            if(routes.Any(r=>(r.SucursalId==id||r.SucursalId is null&&string.Equals(r.Sucursal.Trim(),previous,StringComparison.OrdinalIgnoreCase))&&(!input.Activa||r.SucursalId is null&&input.Nombre!=previous)))
                throw new ArgumentException("La sucursal está asignada a fuentes automáticas. Actualiza esas asignaciones antes de desactivarla; para renombrar una asignación antigua, guarda primero la configuración de fuentes con el selector.");
            q.CommandText="UPDATE core.Sucursal SET Codigo=@Code,Nombre=@Name,Activa=@Active WHERE EmpresaId=@E AND SucursalId=@Id";
        }
        else q.CommandText="INSERT core.Sucursal(EmpresaId,Codigo,Nombre,Activa) OUTPUT inserted.SucursalId VALUES(@E,@Code,@Name,@Active)";
        ZeusRepository.Add(q,"@Code",input.Codigo);ZeusRepository.Add(q,"@Name",input.Nombre);ZeusRepository.Add(q,"@Active",input.Activa);
        if(id is null)id=Convert.ToInt64(await q.ExecuteScalarAsync(ct));else await q.ExecuteNonQueryAsync(ct);
        q.CommandText="INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@E,@U,'GUARDAR_SUCURSAL','core.Sucursal',@Entity,@Json,'ERP')";
        ZeusRepository.Add(q,"@U",user);ZeusRepository.Add(q,"@Entity",id.Value.ToString());ZeusRepository.Add(q,"@Json",JsonSerializer.Serialize(input));
        await q.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);return id.Value;
    }
    public static async Task<BranchResponse> ResolveAsync(SqlConnection c,SqlTransaction tx,long company,ZeusSourceRoute route,CancellationToken ct)
    {
        await using var q=ZeusRepository.Command(c,"SELECT SucursalId,Codigo,Nombre,Activa FROM core.Sucursal WITH(HOLDLOCK) WHERE EmpresaId=@E AND ((@Id IS NOT NULL AND SucursalId=@Id) OR (@Id IS NULL AND Nombre=@Name)) AND Activa=1",company,tx);
        q.Parameters.Add("@Id",SqlDbType.BigInt).Value=(object?)route.SucursalId??DBNull.Value;ZeusRepository.Add(q,"@Name",route.Sucursal.Trim());
        await using var r=await q.ExecuteReaderAsync(ct);
        if(!await r.ReadAsync(ct))throw new ArgumentException("Selecciona una sucursal activa del catálogo de esta empresa en Fuentes automáticas.");
        return new(r.GetInt64(0),r.GetString(1),r.GetString(2),r.GetBoolean(3));
    }
}
public static class BranchCatalogModule
{
    public static void MapBranches(this WebApplication app)
    {
        var group=app.MapGroup("/api/v1/companies/{empresaId:long}/master-data/branches");
        group.AddEndpointFilter(async(context,next)=>{
            try{return await next(context);}
            catch(ArgumentException e){return Results.BadRequest(new{error=e.Message});}
            catch(SqlException e) when(e.Number is 2601 or 2627){return Results.Conflict(new{error="Ya existe una sucursal con ese código o nombre en esta empresa."});}
        });
        group.MapGet("",async(long empresaId,TenantConnectionFactory factory,CancellationToken ct)=>Results.Ok(await new BranchCatalogRepository(factory).ListAsync(empresaId,ct)));
        group.MapPost("",async(long empresaId,SaveBranchRequest input,HttpContext http,TenantConnectionFactory factory,CancellationToken ct)=>Results.Ok(new{id=await new BranchCatalogRepository(factory).SaveAsync(empresaId,null,input,Convert.ToInt64(http.Items["UsuarioId"]),ct)})).RequireErpPermission("SEGURIDAD.PERMISOS.ADMINISTRAR");
        group.MapPut("/{id:long}",async(long empresaId,long id,SaveBranchRequest input,HttpContext http,TenantConnectionFactory factory,CancellationToken ct)=>Results.Ok(new{id=await new BranchCatalogRepository(factory).SaveAsync(empresaId,id,input,Convert.ToInt64(http.Items["UsuarioId"]),ct)})).RequireErpPermission("SEGURIDAD.PERMISOS.ADMINISTRAR");
    }
}
