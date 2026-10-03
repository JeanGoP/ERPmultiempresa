using Microsoft.Data.SqlClient;
using NexoERP.Api.Security;
using NexoERP.Api.Zeus;

namespace NexoERP.Api.Sales;

public static class SalesModule
{
    public static void MapSales(this WebApplication app)
    {
        var group=app.MapGroup("/api/v1/companies/{empresaId:long}");
        group.MapGet("/master-data/clients",async(long empresaId,CustomerRepository customers,CancellationToken ct)=>
            Results.Ok(await customers.ListAsync(empresaId,ct))).RequireErpPermission("MAESTROS.CLIENTE.ADMINISTRAR");
        group.MapPost("/master-data/clients",async(long empresaId,CustomerInput input,HttpContext http,CustomerRepository customers,ZeusRepository settings,ZeusTransport zeus,CancellationToken ct)=>
        {
            try
            {
                var config=await settings.SettingsAsync(empresaId,ct)??throw new ArgumentException("Configura Zeus para esta empresa antes de crear clientes.");
                var city=await zeus.FindCityAsync(empresaId,config.Configuracion,input.CiudadCodigo,ct);
                input=input with{CiudadCodigo=city.CiudadCodigo,Ciudad=city.Ciudad,DepartamentoCodigo=city.DepartamentoCodigo,
                    Departamento=city.Departamento,PaisCodigo=city.PaisCodigo,Pais=city.Pais};
                return Results.Ok(await customers.SaveAsync(empresaId,null,input,Convert.ToInt64(http.Items["UsuarioId"]),ct));
            }
            catch(ArgumentException e){return Results.BadRequest(new{error=e.Message});}
            catch(SqlException e) when(e.Number is 2601 or 2627){return Results.Conflict(new{error="Ya existe otra persona con esta identificación."});}
        }).RequireErpPermission("MAESTROS.CLIENTE.ADMINISTRAR");
        group.MapPut("/master-data/clients/{id:long}",async(long empresaId,long id,CustomerInput input,HttpContext http,CustomerRepository customers,ZeusRepository settings,ZeusTransport zeus,CancellationToken ct)=>
        {
            try
            {
                var config=await settings.SettingsAsync(empresaId,ct)??throw new ArgumentException("Configura Zeus para esta empresa antes de editar clientes.");
                var city=await zeus.FindCityAsync(empresaId,config.Configuracion,input.CiudadCodigo,ct);
                input=input with{CiudadCodigo=city.CiudadCodigo,Ciudad=city.Ciudad,DepartamentoCodigo=city.DepartamentoCodigo,
                    Departamento=city.Departamento,PaisCodigo=city.PaisCodigo,Pais=city.Pais};
                return Results.Ok(await customers.SaveAsync(empresaId,id,input,Convert.ToInt64(http.Items["UsuarioId"]),ct));
            }
            catch(ArgumentException e){return Results.BadRequest(new{error=e.Message});}
            catch(SqlException e) when(e.Number is 2601 or 2627){return Results.Conflict(new{error="Ya existe otra persona con esta identificación."});}
        }).RequireErpPermission("MAESTROS.CLIENTE.ADMINISTRAR");
        group.MapPost("/master-data/clients/{id:long}/zeus/retry",async(long empresaId,long id,CustomerRepository customers,CancellationToken ct)=>
            await customers.RetryZeusAsync(empresaId,id,ct)
                ?Results.Accepted(value:new{estado="PENDIENTE"})
                :Results.Conflict(new{error="El cliente no existe o su estado no admite reintento."}))
            .RequireErpPermission("MAESTROS.CLIENTE.ADMINISTRAR");
        group.MapGet("/zeus/client-catalogs",async(long empresaId,ZeusRepository settings,ZeusTransport zeus,CancellationToken ct)=>
        {
            var config=await settings.SettingsAsync(empresaId,ct);
            return config is null?Results.BadRequest(new{error="Configura Zeus para esta empresa."}):Results.Ok(await zeus.CustomerCatalogsAsync(empresaId,config.Configuracion,ct));
        }).RequireErpPermission("MAESTROS.CLIENTE.ADMINISTRAR");
        group.MapGet("/zeus/cities",async(long empresaId,string q,ZeusRepository settings,ZeusTransport zeus,CancellationToken ct)=>
        {
            try
            {
                var config=await settings.SettingsAsync(empresaId,ct)??throw new ArgumentException("Configura Zeus para consultar ciudades.");
                return Results.Ok(await zeus.SearchCitiesAsync(empresaId,config.Configuracion,q,ct));
            }
            catch(ArgumentException e){return Results.BadRequest(new{error=e.Message});}
        }).RequireErpPermission("MAESTROS.CLIENTE.ADMINISTRAR","MAESTROS.PROVEEDOR.ADMINISTRAR");
    }
}
