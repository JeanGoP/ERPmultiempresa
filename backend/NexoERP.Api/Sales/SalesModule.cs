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

        group.MapGet("/cash-receipts",async(long empresaId,string? q,long? antes,CustomerCashRepository receipts,CancellationToken ct)=>
            Results.Ok(await receipts.ListAsync(empresaId,q,antes,ct))).RequireErpPermission("TESORERIA.RECIBO.CONTABILIZAR");
        group.MapGet("/cash-receipts/options",async(long empresaId,long? clienteId,string? q,CustomerCashRepository receipts,CancellationToken ct)=>
            Results.Ok(await receipts.OptionsAsync(empresaId,clienteId,q,ct))).RequireErpPermission("TESORERIA.RECIBO.CONTABILIZAR");
        group.MapGet("/cash-receipts/accounts",async(long empresaId,ZeusRepository settings,ZeusTransport zeus,CancellationToken ct)=>
        {
            var config=(await settings.SettingsAsync(empresaId,ct)??throw new ArgumentException("Configura Zeus para esta empresa.")).Configuracion;
            return Results.Ok(await zeus.AdvanceAccountsAsync(empresaId,config,ct));
        }).RequireErpPermission("TESORERIA.RECIBO.CONTABILIZAR");
        group.MapPost("/cash-receipts",async(long empresaId,CashReceiptInput input,HttpContext http,CustomerCashRepository receipts,ZeusRepository settings,ZeusTransport zeus,CancellationToken ct)=>
        {
            try
            {
                if(input.Tipo=="NORMAL")
                {
                    var config=(await settings.SettingsAsync(empresaId,ct)??throw new ArgumentException("Configura Zeus.")).Configuracion;
                    if(!(await zeus.AdvanceAccountsAsync(empresaId,config,ct)).Any(a=>a.Codigo==input.CuentaContrapartida))
                        throw new ArgumentException("Selecciona una cuenta de detalle habilitada de Zeus para el recibo normal.");
                }
                return Results.Ok(await receipts.PostAsync(empresaId,input,Convert.ToInt64(http.Items["UsuarioId"]),ct));
            }
            catch(ArgumentException e){return Results.BadRequest(new{error=e.Message});}
            catch(SqlException e) when(e.Number is 2601 or 2627 or 52310){return Results.Conflict(new{error=e.Message});}
        }).RequireErpPermission("TESORERIA.RECIBO.CONTABILIZAR");
        group.MapPost("/cash-receipts/{id:long}/retry",async(long empresaId,long id,CustomerPostingQueue queue,CancellationToken ct)=>
        {await queue.RetryAsync(empresaId,"RECIBO",id,ct);return Results.NoContent();}).RequireErpPermission("TESORERIA.RECIBO.CONTABILIZAR");
        group.MapPost("/cash-receipts/{id:long}/reconcile",async(long empresaId,long id,CustomerPostingQueue queue,ZeusTransport zeus,CancellationToken ct)=>
            Results.Ok(await queue.ReconcileAsync(empresaId,"RECIBO",id,zeus,ct))).RequireErpPermission("SEGURIDAD.PERMISOS.ADMINISTRAR");

        group.MapGet("/sales-invoices",async(long empresaId,string? q,long? antes,SalesInvoiceRepository sales,CancellationToken ct)=>
            Results.Ok(await sales.ListAsync(empresaId,q,antes,ct))).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapGet("/sales-invoices/options",async(long empresaId,long? clienteId,SalesInvoiceRepository sales,CancellationToken ct)=>
            Results.Ok(await sales.OptionsAsync(empresaId,clienteId,ct))).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapGet("/sales-invoices/financing-accounts",async(long empresaId,ZeusRepository settings,ZeusTransport zeus,CancellationToken ct)=>
        {
            var config=(await settings.SettingsAsync(empresaId,ct)??throw new ArgumentException("Configura Zeus para esta empresa.")).Configuracion;
            return Results.Ok((await zeus.AdvanceAccountsAsync(empresaId,config,ct)).Where(a=>a.Codigo.StartsWith("4135",StringComparison.Ordinal)).ToArray());
        }).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapPost("/sales-invoices",async(long empresaId,SalesInvoiceInput input,HttpContext http,SalesInvoiceRepository sales,ZeusRepository settings,ZeusTransport zeus,CancellationToken ct)=>
        {
            try
            {
                if(input.Financiacion>0)
                {
                    var config=(await settings.SettingsAsync(empresaId,ct)??throw new ArgumentException("Configura Zeus.")).Configuracion;
                    if(!(await zeus.AdvanceAccountsAsync(empresaId,config,ct)).Any(a=>a.Codigo==input.CuentaFinanciacion&&a.Codigo.StartsWith("4135",StringComparison.Ordinal)))
                        throw new ArgumentException("Selecciona una cuenta de ingreso 4135 de detalle habilitada en Zeus.");
                }
                return Results.Ok(await sales.PostAsync(empresaId,input,Convert.ToInt64(http.Items["UsuarioId"]),ct));
            }
            catch(ArgumentException e){return Results.BadRequest(new{error=e.Message});}
            catch(SqlException e) when(e.Number is 2601 or 2627 or 52311 || e.Number is >=51200 and <=51299){return Results.Conflict(new{error=e.Message});}
        }).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapPost("/sales-invoices/{id:long}/retry",async(long empresaId,long id,CustomerPostingQueue queue,CancellationToken ct)=>
        {await queue.RetryAsync(empresaId,"FACTURA",id,ct);return Results.NoContent();}).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapPost("/sales-invoices/{id:long}/reconcile",async(long empresaId,long id,CustomerPostingQueue queue,ZeusTransport zeus,CancellationToken ct)=>
            Results.Ok(await queue.ReconcileAsync(empresaId,"FACTURA",id,zeus,ct))).RequireErpPermission("SEGURIDAD.PERMISOS.ADMINISTRAR");
    }
}
