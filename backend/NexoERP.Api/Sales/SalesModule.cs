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

        group.MapGet("/cash-receipts",async(long empresaId,string? q,long? antes,string? tipo,CustomerCashRepository receipts,CancellationToken ct)=>
            Results.Ok(await receipts.ListAsync(empresaId,q,antes,tipo,ct))).RequireErpPermission("TESORERIA.RECIBO.CONTABILIZAR");
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
        {
            try {var fuente=await queue.RetryAsync(empresaId,"RECIBO",id,ct);return Results.Ok(new{estado="PENDIENTE",fuente});}
            catch(ArgumentException e){return Results.Conflict(new{error=e.Message});}
        }).RequireErpPermission("TESORERIA.RECIBO.CONTABILIZAR");
        group.MapPost("/cash-receipts/{id:long}/reconcile",async(long empresaId,long id,CustomerPostingQueue queue,ZeusTransport zeus,CancellationToken ct)=>
            Results.Ok(await queue.ReconcileAsync(empresaId,"RECIBO",id,zeus,ct))).RequireErpPermission("SEGURIDAD.PERMISOS.ADMINISTRAR");

        group.MapGet("/sales-invoices",async(long empresaId,string? q,long? antes,SalesInvoiceRepository sales,CancellationToken ct)=>
            Results.Ok(await sales.ListAsync(empresaId,q,antes,ct))).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapGet("/sales-receivables",async(long empresaId,string? q,string? clase,string? estado,int? banda,DateOnly? desde,DateOnly? hasta,int? pagina,SalesInvoiceRepository sales,CancellationToken ct)=>
        {
            try{return Results.Ok(await sales.ReceivablesAsync(empresaId,q,clase,estado,banda,desde,hasta,pagina??1,ct));}
            catch(ArgumentException e){return Results.BadRequest(new{error=e.Message});}
        }).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapGet("/sales-invoices/{id:long}",async(long empresaId,long id,SalesInvoiceRepository sales,CancellationToken ct)=>
        {
            var invoice=await sales.DetailAsync(empresaId,id,ct);
            return invoice is null?Results.NotFound(new{error="No se encontró la factura en esta empresa."}):Results.Ok(invoice);
        }).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapPut("/sales-invoices/{id:long}/portfolio-class",async(long empresaId,long id,SalesPortfolioClassification input,HttpContext http,SalesInvoiceRepository sales,CancellationToken ct)=>
        {
            try{await sales.ClassifyAsync(empresaId,id,input.ClaseCartera,Convert.ToInt64(http.Items["UsuarioId"]),ct);return Results.NoContent();}
            catch(ArgumentException e){return Results.BadRequest(new{error=e.Message});}
        }).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapGet("/sales-invoices/options",async(long empresaId,long? clienteId,SalesInvoiceRepository sales,CancellationToken ct)=>
            Results.Ok(await sales.OptionsAsync(empresaId,clienteId,ct))).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapGet("/sales-invoices/accounting-dimensions",async(long empresaId,ZeusRepository settings,ZeusTransport zeus,ILogger<SalesInvoiceRepository> logger,HttpContext http,CancellationToken ct)=>
        {
            try
            {
                var config=(await settings.SettingsAsync(empresaId,ct)??throw new ArgumentException("Configura Zeus para esta empresa.")).Configuracion;
                return Results.Ok(await zeus.AccountingDimensionsAsync(empresaId,config,ct));
            }
            catch(ArgumentException e){return Results.BadRequest(new{error=e.Message});}
            catch(Exception e) when(e is not OperationCanceledException)
            {
                logger.LogError(e,"Falló la consulta de dimensiones contables Zeus para la empresa {EmpresaId}; correlación {CorrelationId}.",empresaId,http.TraceIdentifier);
                return Results.Problem(detail:$"Zeus no pudo entregar los centros de costo. Reporta el código {http.TraceIdentifier} a soporte.",statusCode:503);
            }
        }).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapGet("/master-data/sales-concepts",async(long empresaId,SalesConceptRepository concepts,CancellationToken ct)=>
            Results.Ok(await concepts.ListAsync(empresaId,ct))).RequireErpPermission("MAESTROS.CONCEPTO_VENTA.ADMINISTRAR","VENTAS.FACTURA.CONTABILIZAR");
        group.MapGet("/master-data/sales-concepts/accounts",async(long empresaId,ZeusRepository settings,ZeusTransport zeus,CancellationToken ct)=>
        {
            var config=(await settings.SettingsAsync(empresaId,ct)??throw new ArgumentException("Configura Zeus para esta empresa.")).Configuracion;
            return Results.Ok((await zeus.ChartAsync(empresaId,config,ct)).Where(a=>a.Codigo.StartsWith("4",StringComparison.Ordinal)).ToArray());
        }).RequireErpPermission("MAESTROS.CONCEPTO_VENTA.ADMINISTRAR");
        group.MapPost("/master-data/sales-concepts",async(long empresaId,SalesConceptInput input,HttpContext http,SalesConceptRepository concepts,ZeusRepository settings,ZeusTransport zeus,CancellationToken ct)=>
        {
            try
            {
                var config=(await settings.SettingsAsync(empresaId,ct)??throw new ArgumentException("Configura Zeus.")).Configuracion;
                if(!(await zeus.ChartAsync(empresaId,config,ct)).Any(a=>a.Codigo==input.CuentaIngresoZeus&&a.Codigo.StartsWith("4",StringComparison.Ordinal)))
                    throw new ArgumentException("Selecciona una cuenta de ingreso clase 4, de detalle y habilitada en Zeus.");
                return Results.Ok(await concepts.SaveAsync(empresaId,null,input,Convert.ToInt64(http.Items["UsuarioId"]),config,ct));
            }
            catch(ArgumentException e){return Results.BadRequest(new{error=e.Message});}
            catch(SqlException e) when(e.Number is 2601 or 2627){return Results.Conflict(new{error="Ya existe un concepto con ese código."});}
        }).RequireErpPermission("MAESTROS.CONCEPTO_VENTA.ADMINISTRAR");
        group.MapPut("/master-data/sales-concepts/{id:long}",async(long empresaId,long id,SalesConceptInput input,HttpContext http,SalesConceptRepository concepts,ZeusRepository settings,ZeusTransport zeus,CancellationToken ct)=>
        {
            try
            {
                var config=(await settings.SettingsAsync(empresaId,ct)??throw new ArgumentException("Configura Zeus.")).Configuracion;
                if(!(await zeus.ChartAsync(empresaId,config,ct)).Any(a=>a.Codigo==input.CuentaIngresoZeus&&a.Codigo.StartsWith("4",StringComparison.Ordinal)))
                    throw new ArgumentException("Selecciona una cuenta de ingreso clase 4, de detalle y habilitada en Zeus.");
                return Results.Ok(await concepts.SaveAsync(empresaId,id,input,Convert.ToInt64(http.Items["UsuarioId"]),config,ct));
            }
            catch(ArgumentException e){return Results.BadRequest(new{error=e.Message});}
            catch(SqlException e) when(e.Number is 2601 or 2627){return Results.Conflict(new{error="Ya existe un concepto con ese código."});}
        }).RequireErpPermission("MAESTROS.CONCEPTO_VENTA.ADMINISTRAR");
        group.MapPost("/sales-invoices",async(long empresaId,SalesInvoiceInput input,HttpContext http,SalesInvoiceRepository sales,CancellationToken ct)=>
        {
            try
            {
                return Results.Ok(await sales.PostAsync(empresaId,input,Convert.ToInt64(http.Items["UsuarioId"]),ct));
            }
            catch(ArgumentException e){return Results.BadRequest(new{error=e.Message});}
            catch(SqlException e) when(e.Number is 2601 or 2627 or 52311 || e.Number is >=51200 and <=51299){return Results.Conflict(new{error=e.Message});}
        }).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapGet("/sales-price-approvals",async(long empresaId,HttpContext http,SalesPriceApprovalRepository approvals,AuthRepository auth,CancellationToken ct)=>
        {
            var user=Convert.ToInt64(http.Items["UsuarioId"]);
            return Results.Ok(await approvals.ListAsync(empresaId,user,await auth.HasPermissionAsync(user,empresaId,"SEGURIDAD.PERMISOS.ADMINISTRAR",ct),ct));
        }).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR","SEGURIDAD.PERMISOS.ADMINISTRAR");
        group.MapPost("/sales-price-approvals",async(long empresaId,SalesPriceApprovalRequest request,HttpContext http,SalesPriceApprovalRepository approvals,CancellationToken ct)=>
        {
            try{return Results.Ok(await approvals.RequestAsync(empresaId,request,Convert.ToInt64(http.Items["UsuarioId"]),ct));}
            catch(ArgumentException e){return Results.BadRequest(new{error=e.Message});}
            catch(SqlException e) when(e.Number is 2601 or 2627){return Results.Conflict(new{error="La solicitud ya existe. Actualiza el listado."});}
        }).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapPost("/sales-price-approvals/{id:long}/approve",async(long empresaId,long id,SalesPriceApprovalDecision decision,HttpContext http,SalesPriceApprovalRepository approvals,CancellationToken ct)=>
        {
            try{await approvals.DecideAsync(empresaId,id,Convert.ToInt64(http.Items["UsuarioId"]),true,decision.Respuesta,ct);return Results.Ok(new{estado="APROBADA"});}
            catch(ArgumentException e){return Results.Conflict(new{error=e.Message});}
        }).RequireErpPermission("SEGURIDAD.PERMISOS.ADMINISTRAR");
        group.MapPost("/sales-price-approvals/{id:long}/reject",async(long empresaId,long id,SalesPriceApprovalDecision decision,HttpContext http,SalesPriceApprovalRepository approvals,CancellationToken ct)=>
        {
            try{await approvals.DecideAsync(empresaId,id,Convert.ToInt64(http.Items["UsuarioId"]),false,decision.Respuesta,ct);return Results.Ok(new{estado="RECHAZADA"});}
            catch(ArgumentException e){return Results.Conflict(new{error=e.Message});}
        }).RequireErpPermission("SEGURIDAD.PERMISOS.ADMINISTRAR");
        group.MapPost("/sales-price-approvals/{id:long}/issue",async(long empresaId,long id,HttpContext http,SalesPriceApprovalRepository approvals,SalesInvoiceRepository sales,CancellationToken ct)=>
        {
            try
            {
                var user=Convert.ToInt64(http.Items["UsuarioId"]);
                var input=await approvals.ApprovedInvoiceAsync(empresaId,id,user,ct);
                return Results.Ok(await sales.PostAsync(empresaId,input,user,ct));
            }
            catch(ArgumentException e){return Results.Conflict(new{error=e.Message});}
            catch(SqlException e) when(e.Number is 2601 or 2627 or 52311 || e.Number is >=51200 and <=51299){return Results.Conflict(new{error=e.Message});}
        }).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapPost("/sales-invoices/{id:long}/retry",async(long empresaId,long id,CustomerPostingQueue queue,CancellationToken ct)=>
        {
            try {var fuente=await queue.RetryAsync(empresaId,"FACTURA",id,ct);return Results.Ok(new{estado="PENDIENTE",fuente});}
            catch(ArgumentException e){return Results.Conflict(new{error=e.Message});}
        }).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapGet("/sales-invoices/{id:long}/cost-centers",async(long empresaId,long id,SalesInvoiceRepository sales,ZeusRepository settings,CancellationToken ct)=>
        {
            try
            {
                var config=(await settings.SettingsAsync(empresaId,ct)??throw new ArgumentException("Configura Zeus.")).Configuracion;
                return Results.Ok(await sales.MissingCostCentersAsync(empresaId,id,config,ct));
            }
            catch(ArgumentException e){return Results.BadRequest(new{error=e.Message});}
        }).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapPost("/sales-invoices/{id:long}/cost-centers",async(long empresaId,long id,SalesCostCenterCorrection input,HttpContext http,SalesInvoiceRepository sales,ZeusRepository settings,CancellationToken ct)=>
        {
            try
            {
                var config=(await settings.SettingsAsync(empresaId,ct)??throw new ArgumentException("Configura Zeus.")).Configuracion;
                return Results.Ok(new{movimientosCorregidos=await sales.CorrectCostCentersAsync(empresaId,id,input.CentroCosto,Convert.ToInt64(http.Items["UsuarioId"]),config,ct)});
            }
            catch(ArgumentException e){return Results.BadRequest(new{error=e.Message});}
        }).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapPost("/sales-invoices/{id:long}/reconcile",async(long empresaId,long id,CustomerPostingQueue queue,ZeusTransport zeus,CancellationToken ct)=>
            Results.Ok(await queue.ReconcileAsync(empresaId,"FACTURA",id,zeus,ct))).RequireErpPermission("SEGURIDAD.PERMISOS.ADMINISTRAR");
        group.MapGet("/sales-invoices/{id:long}/refinancings",async(long empresaId,long id,PortfolioRefinancingRepository portfolio,CancellationToken ct)=>
            Results.Ok(await portfolio.ListAsync(empresaId,id,ct))).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapGet("/sales-invoices/{id:long}/refinancing-payments",async(long empresaId,long id,CustomerCashRepository receipts,CancellationToken ct)=>
            Results.Ok(await receipts.RefinancingPaymentsAsync(empresaId,id,ct))).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapPost("/sales-invoices/{id:long}/refinancing-payment",async(long empresaId,long id,ExtraordinaryRefinancingPaymentInput input,HttpContext http,CustomerCashRepository receipts,CancellationToken ct)=>
        {
            try{return Results.Ok(await receipts.PostExtraordinaryRefinancingAsync(empresaId,id,input,Convert.ToInt64(http.Items["UsuarioId"]),ct));}
            catch(ArgumentException e){return Results.BadRequest(new{error=e.Message});}
            catch(SqlException e) when(e.Number is 2601 or 2627 or 52310){return Results.Conflict(new{error="La cartera cambió durante el abono. Actualiza la factura y vuelve a intentarlo."});}
        }).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR").RequireErpPermission("TESORERIA.RECIBO.CONTABILIZAR");
        group.MapGet("/sales-invoices/refinancing-options",async(long empresaId,ZeusRepository settings,ZeusTransport zeus,CancellationToken ct)=>
        {
            var config=(await settings.SettingsAsync(empresaId,ct)??throw new ArgumentException("Configura Zeus para esta empresa.")).Configuracion;
            var dimensions=await zeus.AccountingDimensionsAsync(empresaId,config,ct);
            return Results.Ok(new{cuentas=(await zeus.ChartAsync(empresaId,config,ct)).Where(x=>x.Codigo.StartsWith("4",StringComparison.Ordinal)).ToArray(),centrosCosto=dimensions.CentrosCosto,cuentasRequierenCentroCosto=dimensions.CuentasRequierenCentroCosto});
        }).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapPost("/sales-invoices/{id:long}/refinancings",async(long empresaId,long id,PortfolioRefinancingInput input,HttpContext http,PortfolioRefinancingRepository portfolio,CancellationToken ct)=>
        {
            try{return Results.Ok(await portfolio.CreateAsync(empresaId,id,input,Convert.ToInt64(http.Items["UsuarioId"]),ct));}
            catch(ArgumentException e){return Results.BadRequest(new{error=e.Message});}
            catch(SqlException e) when(e.Number is 2601 or 2627){return Results.Conflict(new{error="La nota ya existe o la cartera cambió; actualiza antes de continuar."});}
        }).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapPost("/portfolio-notes/{noteId:long}/retry",async(long empresaId,long noteId,CustomerPostingQueue queue,CancellationToken ct)=>
        {
            try{var source=await queue.RetryAsync(empresaId,"NOTA",noteId,ct);return Results.Ok(new{estado="PENDIENTE",fuente=source});}
            catch(ArgumentException e){return Results.Conflict(new{error=e.Message});}
        }).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
        group.MapPost("/portfolio-notes/{noteId:long}/reconcile",async(long empresaId,long noteId,CustomerPostingQueue queue,ZeusTransport zeus,CancellationToken ct)=>
            Results.Ok(await queue.ReconcileAsync(empresaId,"NOTA",noteId,zeus,ct))).RequireErpPermission("SEGURIDAD.PERMISOS.ADMINISTRAR");
        group.MapPost("/portfolio-notes/{noteId:long}/approve",async(long empresaId,long noteId,HttpContext http,PortfolioRefinancingRepository portfolio,CancellationToken ct)=>
        {
            try{await portfolio.ApproveAsync(empresaId,noteId,Convert.ToInt64(http.Items["UsuarioId"]),ct);return Results.Ok(new{estado="PENDIENTE"});}
            catch(ArgumentException e){return Results.Conflict(new{error=e.Message});}
        }).RequireErpPermission("SEGURIDAD.PERMISOS.ADMINISTRAR");
        group.MapPost("/sales-invoices/{id:long}/refinancings/{noteId:long}/cancel",async(long empresaId,long id,long noteId,HttpContext http,PortfolioRefinancingRepository portfolio,CancellationToken ct)=>
        {
            try{await portfolio.CancelUnsentAsync(empresaId,id,noteId,Convert.ToInt64(http.Items["UsuarioId"]),ct);return Results.NoContent();}
            catch(ArgumentException e){return Results.Conflict(new{error=e.Message});}
        }).RequireErpPermission("VENTAS.FACTURA.CONTABILIZAR");
    }
}
