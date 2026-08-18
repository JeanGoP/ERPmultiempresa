using System.Diagnostics;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Options;
using NexoERP.Api.AdvancedControls;
using NexoERP.Api.Data;
using NexoERP.Api.Inventory;
using NexoERP.Api.MasterData;
using NexoERP.Api.Purchasing;
using NexoERP.Api.Production;
using NexoERP.Api.Security;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddSingleton<TenantConnectionFactory>();
builder.Services.AddScoped<InventoryRepository>();
builder.Services.AddScoped<InventoryOperationsRepository>();
builder.Services.AddScoped<AdvancedControlsRepository>();
builder.Services.AddScoped<MasterDataRepository>();
builder.Services.AddScoped<PurchasingRepository>();
builder.Services.AddScoped<AuthRepository>();
builder.Services.Configure<OutboxOptions>(builder.Configuration.GetSection("Outbox"));
builder.Services.AddHttpClient(nameof(OutboxDispatcherService),client=>client.Timeout=TimeSpan.FromSeconds(15));
builder.Services.AddSingleton<ProductionOperationsRepository>();
builder.Services.AddSingleton<OperationalMetrics>();
builder.Services.AddHostedService<OutboxDispatcherService>();
builder.Services.AddProblemDetails();

var app = builder.Build();
const string ReleaseVersion="2026.08.17.3";
app.UseExceptionHandler();

app.Use(async (context,next) =>
{
    var metrics=context.RequestServices.GetRequiredService<OperationalMetrics>();
    var timer=Stopwatch.StartNew();
    var supplied=context.Request.Headers["X-Correlation-ID"].ToString();
    if(!string.IsNullOrWhiteSpace(supplied)) context.TraceIdentifier=supplied[..Math.Min(supplied.Length,100)];
    context.Response.Headers["X-Correlation-ID"]=context.TraceIdentifier;
    try { await next(); }
    finally { timer.Stop();metrics.RecordRequest(timer.Elapsed,context.Response.StatusCode>=500); }
});

app.Use(async (context,next) =>
{
    try { await next(); }
    catch(SqlException error)
    {
        if(context.Response.HasStarted) throw;
        var retryable=error.Number is 1205 or 1222;
        context.Response.StatusCode=error.Number is 2601 or 2627 or 1205 or 1222 || error.Number is >= 51000 and <= 52999
            ? StatusCodes.Status409Conflict : StatusCodes.Status500InternalServerError;
        await context.Response.WriteAsJsonAsync(new
        {
            error=context.Response.StatusCode==500?"Ocurrio un error interno al procesar la operacion.":error.Message,
            code=error.Number,
            retryable,
            correlationId=context.TraceIdentifier
        });
    }
});

app.Use(async (context,next) =>
{
    if (context.Request.Path.StartsWithSegments("/api/v1/health") || context.Request.Path.StartsWithSegments("/api/v1/auth/login"))
    {
        await next();
        return;
    }
    var authorization=context.Request.Headers.Authorization.ToString();
    if(!authorization.StartsWith("Bearer ",StringComparison.OrdinalIgnoreCase))
    {
        context.Response.StatusCode=StatusCodes.Status401Unauthorized;
        await context.Response.WriteAsJsonAsync(new { error="Se requiere una sesión válida." });
        return;
    }
    var auth=context.RequestServices.GetRequiredService<AuthRepository>();
    var user=await auth.ValidateAsync(authorization[7..].Trim(),context.RequestAborted);
    if(user is null)
    {
        context.Response.StatusCode=StatusCodes.Status401Unauthorized;
        await context.Response.WriteAsJsonAsync(new { error="La sesión expiró o fue revocada." });
        return;
    }
    context.Items["UsuarioId"]=user.UsuarioId;
    context.Items["EsSuperAdministrador"]=user.EsSuperAdministrador;
    if(context.Request.RouteValues.TryGetValue("empresaId",out var rawEmpresa) && long.TryParse(Convert.ToString(rawEmpresa),out var empresaId)
       && !user.EsSuperAdministrador && !await auth.HasCompanyAccessAsync(user.UsuarioId,empresaId,context.RequestAborted))
    {
        context.Response.StatusCode=StatusCodes.Status403Forbidden;
        await context.Response.WriteAsJsonAsync(new { error="El usuario no tiene acceso a la empresa solicitada." });
        return;
    }
    await next();
});

app.MapGet("/api/v1/health", async (TenantConnectionFactory connections, CancellationToken cancellationToken) =>
{
    await using var connection = await connections.OpenAsync(null, true, cancellationToken);
    await using var command = connection.CreateCommand();
    command.CommandText = "SELECT COUNT(*) FROM core.SchemaMigration;";
    var migrations = Convert.ToInt32(await command.ExecuteScalarAsync(cancellationToken));
    return Results.Ok(new { status = "ok", database = "connected", migrations, release=ReleaseVersion });
});
app.MapGet("/api/v1/health/live",()=>Results.Ok(new { status="live",utc=DateTime.UtcNow }));
app.MapGet("/api/v1/health/ready",async(ProductionOperationsRepository operations,IOptions<OutboxOptions> options,CancellationToken ct)=>
{
    var health=await operations.GetPlatformHealthAsync(ct);var ready=health.Migrations>=38&&health.DiscardedOutbox==0;
    var productionIntegration=string.Equals(options.Value.DeliveryMode,"Webhook",StringComparison.OrdinalIgnoreCase)&&Uri.IsWellFormedUriString(options.Value.WebhookUrl,UriKind.Absolute);
    return Results.Json(new { status=ready?"ready":"degraded",database="connected",health.Migrations,health.PendingOutbox,health.DiscardedOutbox,health.OldestPendingUtc,integrationMode=options.Value.DeliveryMode,productionIntegration },statusCode:ready?200:503);
});

app.MapPost("/api/v1/auth/login", async (LoginRequest input,HttpContext context,AuthRepository auth,CancellationToken cancellationToken) =>
{
    if(string.IsNullOrWhiteSpace(input.Correo) || string.IsNullOrEmpty(input.Password))
        return Results.ValidationProblem(new Dictionary<string,string[]> { ["credenciales"]=["Correo y contraseña son obligatorios."] });
    var result=await auth.LoginAsync(input,context.Connection.RemoteIpAddress?.ToString(),cancellationToken);
    return result is null?Results.Unauthorized():Results.Ok(result);
});

app.MapGet("/api/v1/companies", async (HttpContext context,AuthRepository auth,CancellationToken cancellationToken) =>
    Results.Ok(await auth.GetCompaniesAsync(Convert.ToInt64(context.Items["UsuarioId"]),cancellationToken)));
app.MapPost("/api/v1/companies",async(CreateCompanyRequest input,HttpContext context,AuthRepository auth,CancellationToken ct)=>
{
    if(string.IsNullOrWhiteSpace(input.Codigo)||string.IsNullOrWhiteSpace(input.Nit)||string.IsNullOrWhiteSpace(input.RazonSocial))
        return Results.ValidationProblem(new Dictionary<string,string[]> { ["empresa"]=["Código, NIT y razón social son obligatorios."] });
    if(input.Codigo.Trim().Length>20||input.Nit.Trim().Length>20||input.RazonSocial.Trim().Length>200)
        return Results.ValidationProblem(new Dictionary<string,string[]> { ["empresa"]=["Uno de los campos excede la longitud permitida."] });
    try
    {
        var created=await auth.CreateCompanyAsync(Convert.ToInt64(context.Items["UsuarioId"]),input,ct);
        return Results.Created($"/api/v1/companies/{created.EmpresaId}",created);
    }
    catch(ArgumentException error)
    {
        return Results.ValidationProblem(new Dictionary<string,string[]> { ["empresa"]=[error.Message] });
    }
    catch(SqlException error) when(error.Number is 2601 or 2627)
    {
        return Results.Conflict(new { error="Ya existe una empresa con el mismo código o NIT." });
    }
    catch(SqlException error)
    {
        app.Logger.LogError(error,"No fue posible crear la empresa desde el aprovisionamiento global.");
        return Results.Json(new { error="SQL Server rechazó la creación de la empresa.",code=$"SQL-{error.Number}",release=ReleaseVersion },statusCode:StatusCodes.Status500InternalServerError);
    }
}).RequireSuperAdministrator();
app.MapGet("/api/v1/companies/{empresaId:long}/operations/status",async(long empresaId,ProductionOperationsRepository operations,OperationalMetrics metrics,CancellationToken ct)=>Results.Ok(new { company=await operations.GetCompanyStatusAsync(empresaId,ct),runtime=metrics.Snapshot() })).RequireErpPermission("SEGURIDAD.PERMISOS.ADMINISTRAR");
app.MapGet("/api/v1/companies/{empresaId:long}/operations/alerts",async(long empresaId,ProductionOperationsRepository operations,CancellationToken ct)=>Results.Ok(await operations.GetAlertsAsync(empresaId,ct))).RequireErpPermission("SEGURIDAD.PERMISOS.ADMINISTRAR");
app.MapPost("/api/v1/companies/{empresaId:long}/operations/outbox/{eventId:long}/retry",async(long empresaId,long eventId,ProductionOperationsRepository operations,CancellationToken ct)=>{await operations.RetryAsync(empresaId,eventId,ct);return Results.Accepted();}).RequireErpPermission("SEGURIDAD.PERMISOS.ADMINISTRAR");

app.MapGet("/api/v1/companies/{empresaId:long}/warehouses", async (long empresaId, InventoryRepository inventory, CancellationToken cancellationToken) =>
    Results.Ok(await inventory.GetWarehousesAsync(empresaId, cancellationToken)));
app.MapGet("/api/v1/companies/{empresaId:long}/inventory-periods", async (long empresaId,InventoryRepository inventory,CancellationToken cancellationToken) =>
    Results.Ok(await inventory.GetPeriodsAsync(empresaId,cancellationToken)));
app.MapGet("/api/v1/companies/{empresaId:long}/accounting-periods", async (long empresaId,PurchasingRepository purchasing,CancellationToken cancellationToken) =>
    Results.Ok(await purchasing.GetAccountingPeriodsAsync(empresaId,cancellationToken)));
app.MapGet("/api/v1/companies/{empresaId:long}/accounting-accounts", async (long empresaId,PurchasingRepository purchasing,CancellationToken cancellationToken) =>
    Results.Ok(await purchasing.GetAccountingAccountsAsync(empresaId,cancellationToken)));

app.MapGet("/api/v1/companies/{empresaId:long}/master-data/suppliers", async (long empresaId,MasterDataRepository masters,CancellationToken ct) => Results.Ok(await masters.GetSuppliersAsync(empresaId,ct)));
app.MapGet("/api/v1/companies/{empresaId:long}/master-data/units", async (long empresaId,MasterDataRepository masters,CancellationToken ct) => Results.Ok(await masters.GetUnitsAsync(empresaId,ct)));
app.MapGet("/api/v1/companies/{empresaId:long}/master-data/articles", async (long empresaId,MasterDataRepository masters,CancellationToken ct) => Results.Ok(await masters.GetArticlesAsync(empresaId,ct)));
app.MapGet("/api/v1/companies/{empresaId:long}/master-data/item-mappings", async (long empresaId,long? terceroId,MasterDataRepository masters,CancellationToken ct) => Results.Ok(await masters.GetMappingsAsync(empresaId,terceroId,ct)));

app.MapPost("/api/v1/companies/{empresaId:long}/master-data/suppliers", async (long empresaId,SaveSupplierRequest input,HttpContext context,MasterDataRepository masters,CancellationToken ct) =>
{
    if(string.IsNullOrWhiteSpace(input.NumeroIdentificacion)||string.IsNullOrWhiteSpace(input.RazonSocial)) return Results.ValidationProblem(new Dictionary<string,string[]> { ["proveedor"]=["Identificación y razón social son obligatorias."] });
    return Results.Ok(await masters.SaveSupplierAsync(empresaId,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct));
}).RequireErpPermission("MAESTROS.PROVEEDOR.ADMINISTRAR");

app.MapPost("/api/v1/companies/{empresaId:long}/master-data/units", async (long empresaId,SaveUnitRequest input,HttpContext context,MasterDataRepository masters,CancellationToken ct) =>
{
    if(string.IsNullOrWhiteSpace(input.Codigo)||string.IsNullOrWhiteSpace(input.Nombre)||string.IsNullOrWhiteSpace(input.Simbolo)) return Results.ValidationProblem(new Dictionary<string,string[]> { ["unidad"]=["Código, nombre y símbolo son obligatorios."] });
    return Results.Ok(await masters.SaveUnitAsync(empresaId,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct));
}).RequireErpPermission("MAESTROS.INVENTARIO.ADMINISTRAR");

app.MapPost("/api/v1/companies/{empresaId:long}/master-data/articles", async (long empresaId,SaveArticleRequest input,HttpContext context,MasterDataRepository masters,CancellationToken ct) =>
{
    if(string.IsNullOrWhiteSpace(input.Codigo)||string.IsNullOrWhiteSpace(input.Descripcion)||input.UnidadBaseId<=0) return Results.ValidationProblem(new Dictionary<string,string[]> { ["articulo"]=["Código, descripción y unidad base son obligatorios."] });
    return Results.Ok(await masters.SaveArticleAsync(empresaId,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct));
}).RequireErpPermission("MAESTROS.ARTICULO.ADMINISTRAR");

app.MapPost("/api/v1/companies/{empresaId:long}/master-data/articles/{articuloId:long}/units", async (long empresaId,long articuloId,SaveArticleUnitRequest input,HttpContext context,MasterDataRepository masters,CancellationToken ct) =>
{
    if(input.UnidadMedidaId<=0||input.FactorAUnidadBase<=0) return Results.ValidationProblem(new Dictionary<string,string[]> { ["conversion"]=["Unidad y factor mayor que cero son obligatorios."] });
    return Results.Ok(await masters.SaveArticleUnitAsync(empresaId,articuloId,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct));
}).RequireErpPermission("MAESTROS.ARTICULO.ADMINISTRAR");

app.MapPost("/api/v1/companies/{empresaId:long}/master-data/warehouses", async (long empresaId,SaveWarehouseRequest input,HttpContext context,MasterDataRepository masters,CancellationToken ct) =>
{
    if(string.IsNullOrWhiteSpace(input.Codigo)||string.IsNullOrWhiteSpace(input.Nombre)) return Results.ValidationProblem(new Dictionary<string,string[]> { ["bodega"]=["Código y nombre son obligatorios."] });
    return Results.Ok(await masters.SaveWarehouseAsync(empresaId,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct));
}).RequireErpPermission("MAESTROS.INVENTARIO.ADMINISTRAR");

app.MapPost("/api/v1/companies/{empresaId:long}/master-data/item-mappings", async (long empresaId,SaveItemMappingRequest input,HttpContext context,MasterDataRepository masters,CancellationToken ct) =>
{
    if(input.TerceroId<=0||input.ArticuloId<=0||string.IsNullOrWhiteSpace(input.CodigoExterno)||input.FactorAUnidadBase<=0) return Results.ValidationProblem(new Dictionary<string,string[]> { ["homologacion"]=["Proveedor, código externo, artículo y factor válido son obligatorios."] });
    return Results.Ok(await masters.SaveMappingAsync(empresaId,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct));
}).RequireErpPermission("COMPRAS.HOMOLOGACION.ADMINISTRAR");

app.MapGet("/api/v1/companies/{empresaId:long}/inventory/balances", async (long empresaId, InventoryRepository inventory, CancellationToken cancellationToken) =>
    Results.Ok(await inventory.GetBalancesAsync(empresaId, cancellationToken)));
app.MapGet("/api/v1/companies/{empresaId:long}/inventory/stock", async (long empresaId,long? bodegaId,string? q,InventoryRepository inventory,CancellationToken ct) => Results.Ok(await inventory.GetDetailedBalancesAsync(empresaId,bodegaId,q,ct)));
app.MapGet("/api/v1/companies/{empresaId:long}/inventory/kardex", async (long empresaId,DateOnly? desde,DateOnly? hasta,long? bodegaId,long? articuloId,string? q,InventoryRepository inventory,CancellationToken ct) => Results.Ok(await inventory.GetKardexAsync(empresaId,desde,hasta,bodegaId,articuloId,q,ct)));
app.MapGet("/api/v1/companies/{empresaId:long}/inventory/expiry-alerts", async (long empresaId,int? dias,long? bodegaId,InventoryRepository inventory,CancellationToken ct) => Results.Ok(await inventory.GetExpiryAlertsAsync(empresaId,dias??90,bodegaId,ct)));

app.MapGet("/api/v1/companies/{empresaId:long}/permissions", async (long empresaId,HttpContext context,AuthRepository auth,CancellationToken cancellationToken) =>
    Results.Ok(await auth.GetPermissionsAsync(Convert.ToInt64(context.Items["UsuarioId"]),empresaId,cancellationToken)));

app.MapGet("/api/v1/companies/{empresaId:long}/inventory/history", async (long empresaId,DateOnly fecha,long? bodegaId,long? articuloId,InventoryRepository inventory,CancellationToken cancellationToken) =>
    Results.Ok(await inventory.GetInventoryAtAsync(empresaId,fecha,bodegaId,articuloId,cancellationToken)));

app.MapGet("/api/v1/companies/{empresaId:long}/inventory/serialized-units", async (long empresaId,long? bodegaId,string? estado,string? q,InventoryRepository inventory,CancellationToken cancellationToken) => Results.Ok(await inventory.GetSerializedUnitsAsync(empresaId,bodegaId,estado,q,cancellationToken)));

app.MapGet("/api/v1/companies/{empresaId:long}/costs/concepts",async(long empresaId,AdvancedControlsRepository controls,CancellationToken ct)=>Results.Ok(await controls.GetCostConceptsAsync(empresaId,ct)));
app.MapGet("/api/v1/companies/{empresaId:long}/costs/landed/sources",async(long empresaId,string? q,AdvancedControlsRepository controls,CancellationToken ct)=>Results.Ok(await controls.GetLandedCostSourcesAsync(empresaId,q,ct)));
app.MapGet("/api/v1/companies/{empresaId:long}/costs/landed",async(long empresaId,AdvancedControlsRepository controls,CancellationToken ct)=>Results.Ok(await controls.GetLandedCostsAsync(empresaId,ct)));
app.MapPost("/api/v1/companies/{empresaId:long}/costs/landed",async(long empresaId,CreateLandedCostRequest input,HttpContext context,AdvancedControlsRepository controls,CancellationToken ct)=>
{
    if(input.ConceptoCostoId<=0||input.TerceroId<=0||string.IsNullOrWhiteSpace(input.NumeroSoporte)||input.ValorDistribuible<=0||input.Lineas.Count==0) return Results.ValidationProblem(new Dictionary<string,string[]> { ["costo"]=["Concepto, proveedor, soporte, valor y líneas objetivo son obligatorios."] });
    var result=await controls.CreateLandedCostAsync(empresaId,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct);return result.YaExistia?Results.Ok(result):Results.Created($"/api/v1/companies/{empresaId}/landed-cost-distributions/{result.DistribucionCostoId}",result);
}).RequireErpPermission("COSTOS.DISTRIBUCION.APROBAR");
app.MapGet("/api/v1/companies/{empresaId:long}/costs/books",async(long empresaId,AdvancedControlsRepository controls,CancellationToken ct)=>Results.Ok(await controls.GetCostBooksAsync(empresaId,ct)));
app.MapPost("/api/v1/companies/{empresaId:long}/costs/books",async(long empresaId,CreateCostBookRequest input,AdvancedControlsRepository controls,CancellationToken ct)=>
{
    if(string.IsNullOrWhiteSpace(input.Codigo)||string.IsNullOrWhiteSpace(input.Nombre)||input.Categoria is not ("OPERATIVO" or "CONTABLE" or "FISCAL" or "GERENCIAL" or "COMERCIAL")||input.FormulaValoracion is not ("PROMEDIO_MOVIL" or "PROMEDIO_PERIODICO" or "PEPS" or "IDENTIFICACION_ESPECIFICA")) return Results.ValidationProblem(new Dictionary<string,string[]> { ["libro"]=["Código, nombre, categoría y fórmula válidos son obligatorios."] });
    return Results.Ok(await controls.CreateCostBookAsync(empresaId,input,ct));
}).RequireErpPermission("COSTOS.DISTRIBUCION.APROBAR");
app.MapGet("/api/v1/companies/{empresaId:long}/costs/groups",async(long empresaId,AdvancedControlsRepository controls,CancellationToken ct)=>Results.Ok(await controls.GetInventoryGroupsAsync(empresaId,ct)));
app.MapPost("/api/v1/companies/{empresaId:long}/costs/groups",async(long empresaId,CreateInventoryGroupRequest input,AdvancedControlsRepository controls,CancellationToken ct)=>
{
    if(string.IsNullOrWhiteSpace(input.Codigo)||string.IsNullOrWhiteSpace(input.Nombre)||string.IsNullOrWhiteSpace(input.NaturalezaUso)) return Results.ValidationProblem(new Dictionary<string,string[]> { ["grupo"]=["Código, nombre y naturaleza de uso son obligatorios."] });
    return Results.Ok(await controls.CreateInventoryGroupAsync(empresaId,input,ct));
}).RequireErpPermission("COSTOS.DISTRIBUCION.APROBAR");
app.MapGet("/api/v1/companies/{empresaId:long}/costs/policies",async(long empresaId,AdvancedControlsRepository controls,CancellationToken ct)=>Results.Ok(await controls.GetCostPoliciesAsync(empresaId,ct)));
app.MapPost("/api/v1/companies/{empresaId:long}/costs/policies",async(long empresaId,SaveCostPolicyRequest input,HttpContext context,AdvancedControlsRepository controls,CancellationToken ct)=>Results.Ok(await controls.SaveCostPolicyAsync(empresaId,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct))).RequireErpPermission("COSTOS.DISTRIBUCION.APROBAR");
app.MapGet("/api/v1/companies/{empresaId:long}/costs/book-balances",async(long empresaId,long? libroId,AdvancedControlsRepository controls,CancellationToken ct)=>Results.Ok(await controls.GetCostBookBalancesAsync(empresaId,libroId,ct)));
app.MapGet("/api/v1/companies/{empresaId:long}/inventory/net-values",async(long empresaId,AdvancedControlsRepository controls,CancellationToken ct)=>Results.Ok(await controls.GetNetValuesAsync(empresaId,ct)));
app.MapGet("/api/v1/companies/{empresaId:long}/inventory/impairments",async(long empresaId,AdvancedControlsRepository controls,CancellationToken ct)=>Results.Ok(await controls.GetImpairmentsAsync(empresaId,ct)));
app.MapGet("/api/v1/companies/{empresaId:long}/inventory/negative-exceptions",async(long empresaId,AdvancedControlsRepository controls,CancellationToken ct)=>Results.Ok(await controls.GetNegativeExceptionsAsync(empresaId,ct)));
app.MapGet("/api/v1/companies/{empresaId:long}/inventory/negative-exceptions/{id:long}/regularization-sources",async(long empresaId,long id,AdvancedControlsRepository controls,CancellationToken ct)=>Results.Ok(await controls.GetNegativeSourcesAsync(empresaId,id,ct)));
app.MapGet("/api/v1/companies/{empresaId:long}/physical-counts",async(long empresaId,AdvancedControlsRepository controls,CancellationToken ct)=>Results.Ok(await controls.GetPhysicalCountsAsync(empresaId,ct)));
app.MapGet("/api/v1/companies/{empresaId:long}/physical-counts/{id:long}/lines",async(long empresaId,long id,AdvancedControlsRepository controls,CancellationToken ct)=>Results.Ok(await controls.GetPhysicalCountLinesAsync(empresaId,id,ct)));
app.MapPost("/api/v1/companies/{empresaId:long}/physical-counts",async(long empresaId,CreatePhysicalCountRequest input,HttpContext context,AdvancedControlsRepository controls,CancellationToken ct)=>
{
    if(string.IsNullOrWhiteSpace(input.Numero)||input.BodegaId<=0) return Results.ValidationProblem(new Dictionary<string,string[]> { ["conteo"]=["Número y bodega son obligatorios."] });
    var result=await controls.CreatePhysicalCountAsync(empresaId,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct);return result.YaExistia==true?Results.Ok(result):Results.Created($"/api/v1/companies/{empresaId}/physical-counts/{result.ConteoFisicoId}",result);
}).RequireErpPermission("INVENTARIO.CONTEO.INICIAR");
app.MapPost("/api/v1/companies/{empresaId:long}/physical-counts/{id:long}/start",async(long empresaId,long id,PostDocumentRequest input,HttpContext context,AdvancedControlsRepository controls,CancellationToken ct)=>Results.Ok(await controls.StartPhysicalCountAsync(empresaId,id,Convert.ToInt64(context.Items["UsuarioId"]),ct))).RequireErpPermission("INVENTARIO.CONTEO.INICIAR");
app.MapPost("/api/v1/companies/{empresaId:long}/physical-count-lines/{lineId:long}/captures",async(long empresaId,long lineId,CaptureCountRequest input,HttpContext context,AdvancedControlsRepository controls,CancellationToken ct)=>
{
    if(input.NumeroConteo<=0||input.CantidadContada<0) return Results.ValidationProblem(new Dictionary<string,string[]> { ["captura"]=["Número de conteo y cantidad no negativa son obligatorios."] });await controls.CaptureCountAsync(empresaId,lineId,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct);return Results.NoContent();
}).RequireErpPermission("INVENTARIO.CONTEO.CAPTURAR");
app.MapPost("/api/v1/companies/{empresaId:long}/physical-counts/{id:long}/review",async(long empresaId,long id,PostDocumentRequest input,HttpContext context,AdvancedControlsRepository controls,CancellationToken ct)=>Results.Ok(await controls.ReviewPhysicalCountAsync(empresaId,id,Convert.ToInt64(context.Items["UsuarioId"]),ct))).RequireErpPermission("INVENTARIO.CONTEO.CAPTURAR");
app.MapPost("/api/v1/companies/{empresaId:long}/physical-counts/{id:long}/approve",async(long empresaId,long id,ApprovePhysicalCountRequest input,HttpContext context,AdvancedControlsRepository controls,CancellationToken ct)=>
{
    if(input.Lineas.Count==0||input.Lineas.Any(x=>x.CantidadAprobada<0)) return Results.ValidationProblem(new Dictionary<string,string[]> { ["aprobacion"]=["Debe aprobar una cantidad no negativa por cada línea."] });return Results.Ok(await controls.ApprovePhysicalCountAsync(empresaId,id,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct));
}).RequireErpPermission("INVENTARIO.CONTEO.APROBAR");
app.MapGet("/api/v1/companies/{empresaId:long}/inventory/control-periods",async(long empresaId,AdvancedControlsRepository controls,CancellationToken ct)=>Results.Ok(await controls.GetPeriodsAsync(empresaId,ct)));
app.MapGet("/api/v1/companies/{empresaId:long}/inventory/reconciliations",async(long empresaId,AdvancedControlsRepository controls,CancellationToken ct)=>Results.Ok(await controls.GetReconciliationsAsync(empresaId,ct)));
app.MapGet("/api/v1/companies/{empresaId:long}/inventory/reversible-movements",async(long empresaId,AdvancedControlsRepository controls,CancellationToken ct)=>Results.Ok(await controls.GetReversibleMovementsAsync(empresaId,ct)));
app.MapGet("/api/v1/companies/{empresaId:long}/inventory/audit",async(long empresaId,AdvancedControlsRepository controls,CancellationToken ct)=>Results.Ok(await controls.GetAuditAsync(empresaId,ct)));

app.MapPost("/api/v1/companies/{empresaId:long}/inventory/entries", async (long empresaId, PostInventoryEntryRequest input, HttpContext context, InventoryRepository inventory, CancellationToken cancellationToken) =>
{
    if (input.Cantidad <= 0 || input.CostoUnitario < 0)
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["linea"] = ["La cantidad debe ser positiva y el costo no puede ser negativo."] });
    try
    {
        return Results.Ok(await inventory.PostEntryAsync(empresaId, input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) }, cancellationToken));
    }
    catch (SqlException error) when (error.Number is >= 51100 and <= 51299)
    {
        return Results.Conflict(new { error = error.Message, code = error.Number });
    }
}).RequireErpPermission("COMPRAS.RECEPCION.CONTABILIZAR");

app.MapPost("/api/v1/companies/{empresaId:long}/supplier-documents", async (long empresaId, CreateSupplierDocumentRequest input, HttpContext context, PurchasingRepository purchasing, CancellationToken cancellationToken) =>
{
    if (input.Lineas.Count == 0)
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["lineas"] = ["El documento debe contener al menos una línea."] });
    try
    {
        var result = await purchasing.CreateDocumentAsync(empresaId, input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) }, cancellationToken);
        return result.YaExistia ? Results.Ok(result) : Results.Created($"/api/v1/companies/{empresaId}/supplier-documents/{result.DocumentoProveedorId}", result);
    }
    catch (ArgumentException error)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["clasificacion"] = [error.Message] });
    }
    catch (SqlException error) when (error.Number is >= 51300 and <= 51319)
    {
        return Results.Conflict(new { error = error.Message, code = error.Number });
    }
}).RequireErpPermission("COMPRAS.DOCUMENTO.CREAR");

app.MapGet("/api/v1/companies/{empresaId:long}/supplier-documents/{documentoId:long}", async (long empresaId,long documentoId,PurchasingRepository purchasing,CancellationToken cancellationToken) =>
{
    var result=await purchasing.GetWorkflowAsync(empresaId,documentoId,cancellationToken);
    return result is null?Results.NotFound():Results.Ok(result);
});

app.MapPost("/api/v1/companies/{empresaId:long}/supplier-documents/{documentoId:long}/prepare", async (long empresaId, long documentoId, PrepareSupplierDocumentRequest input, HttpContext context, PurchasingRepository purchasing, CancellationToken cancellationToken) =>
{
    try
    {
        return Results.Ok(await purchasing.PrepareAsync(empresaId, documentoId, input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) }, cancellationToken));
    }
    catch (SqlException error) when (error.Number is >= 51320 and <= 51339)
    {
        return Results.Conflict(new { error = error.Message, code = error.Number });
    }
}).RequireErpPermission("COMPRAS.DOCUMENTO.CREAR");

app.MapPost("/api/v1/companies/{empresaId:long}/receipts/{recepcionId:long}/post", async (long empresaId, long recepcionId, PostReceiptRequest input, HttpContext context, PurchasingRepository purchasing, CancellationToken cancellationToken) =>
{
    try
    {
        return Results.Ok(await purchasing.PostReceiptAsync(empresaId, recepcionId, input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) }, cancellationToken));
    }
    catch (SqlException error) when (error.Number is >= 51500 and <= 51599)
    {
        return Results.Conflict(new { error = error.Message, code = error.Number });
    }
}).RequireErpPermission("COMPRAS.RECEPCION.CONTABILIZAR");

app.MapGet("/api/v1/companies/{empresaId:long}/receipts/{recepcionId:long}/movements", async (long empresaId,long recepcionId,PurchasingRepository purchasing,CancellationToken cancellationToken) =>
    Results.Ok(await purchasing.GetReceiptMovementsAsync(empresaId,recepcionId,cancellationToken)));

app.MapPost("/api/v1/companies/{empresaId:long}/service-accruals/{causacionId:long}/post", async (long empresaId, long causacionId, PostServiceAccrualRequest input, HttpContext context, PurchasingRepository purchasing, CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(input.CuentaPorPagarCodigo))
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["cuentaPorPagarCodigo"] = ["La cuenta por pagar es obligatoria."] });
    try
    {
        return Results.Ok(await purchasing.PostServiceAccrualAsync(empresaId, causacionId, input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) }, cancellationToken));
    }
    catch (SqlException error) when (error.Number is >= 51600 and <= 51699)
    {
        return Results.Conflict(new { error = error.Message, code = error.Number });
    }
}).RequireErpPermission("COMPRAS.SERVICIO.CAUSAR");

app.MapPut("/api/v1/companies/{empresaId:long}/service-accruals/{causacionId:long}/accounts", async (long empresaId,long causacionId,AssignServiceAccountsRequest input,PurchasingRepository purchasing,CancellationToken cancellationToken) =>
{
    if(input.Lineas.Count==0) return Results.ValidationProblem(new Dictionary<string,string[]> { ["lineas"]=["Debe asignar las cuentas de las líneas."] });
    try { return Results.Ok(await purchasing.AssignServiceAccountsAsync(empresaId,causacionId,input,cancellationToken)); }
    catch(SqlException error) when(error.Number is >= 51896 and <= 51901) { return Results.Conflict(new { error=error.Message,code=error.Number }); }
}).RequireErpPermission("COMPRAS.SERVICIO.CAUSAR");

app.MapGet("/api/v1/companies/{empresaId:long}/service-accruals/{causacionId:long}", async (long empresaId,long causacionId,PurchasingRepository purchasing,CancellationToken cancellationToken) =>
{
    var result=await purchasing.GetServiceAccrualAsync(empresaId,causacionId,cancellationToken);
    return result is null?Results.NotFound():Results.Ok(result);
});

app.MapPost("/api/v1/companies/{empresaId:long}/transfers/{id:long}/dispatch", async (long empresaId,long id,PostTransferRequest input,HttpContext context,InventoryOperationsRepository operations,CancellationToken ct) =>
    Results.Ok(await operations.DispatchTransferAsync(empresaId,id,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct))).RequireErpPermission("INVENTARIO.TRASLADO.DESPACHAR");
app.MapPost("/api/v1/companies/{empresaId:long}/transfers/{id:long}/receive", async (long empresaId,long id,PostTransferRequest input,HttpContext context,InventoryOperationsRepository operations,CancellationToken ct) =>
    Results.Ok(await operations.ReceiveTransferAsync(empresaId,id,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct))).RequireErpPermission("INVENTARIO.TRASLADO.RECIBIR");
app.MapPost("/api/v1/companies/{empresaId:long}/supplier-returns/{id:long}/post", async (long empresaId,long id,PostDocumentRequest input,HttpContext context,InventoryOperationsRepository operations,CancellationToken ct) =>
    Results.Ok(await operations.PostReturnAsync(empresaId,id,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct))).RequireErpPermission("COMPRAS.DEVOLUCION.CONTABILIZAR");
app.MapPost("/api/v1/companies/{empresaId:long}/sales-returns/{id:long}/post", async (long empresaId,long id,PostDocumentRequest input,HttpContext context,InventoryOperationsRepository operations,CancellationToken ct) =>
    Results.Ok(await operations.PostSalesReturnAsync(empresaId,id,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct))).RequireErpPermission("VENTAS.DEVOLUCION.CONTABILIZAR");
app.MapPost("/api/v1/companies/{empresaId:long}/transfers", async (long empresaId,CreateTransferRequest input,HttpContext context,InventoryOperationsRepository operations,CancellationToken ct) =>
{
    if(string.IsNullOrWhiteSpace(input.Numero)||input.BodegaOrigenId<=0||input.BodegaDestinoId<=0||input.BodegaOrigenId==input.BodegaDestinoId||input.Lineas.Count==0||input.Lineas.Any(x=>x.ArticuloId<=0||x.Cantidad<=0)) return Results.ValidationProblem(new Dictionary<string,string[]> { ["traslado"]=["Número, bodegas diferentes y líneas con cantidades positivas son obligatorios."] });
    var result=await operations.CreateTransferAsync(empresaId,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct);return result.YaExistia?Results.Ok(result):Results.Created($"/api/v1/companies/{empresaId}/transfers/{result.DocumentoId}",result);
}).RequireErpPermission("INVENTARIO.TRASLADO.DESPACHAR");
app.MapGet("/api/v1/companies/{empresaId:long}/supplier-returns/sources", async (long empresaId,string? q,InventoryOperationsRepository operations,CancellationToken ct) => Results.Ok(await operations.GetSupplierReturnSourcesAsync(empresaId,q,ct)));
app.MapPost("/api/v1/companies/{empresaId:long}/supplier-returns", async (long empresaId,CreateSupplierReturnRequest input,HttpContext context,InventoryOperationsRepository operations,CancellationToken ct) =>
{
    if(string.IsNullOrWhiteSpace(input.Numero)||string.IsNullOrWhiteSpace(input.Motivo)||input.Lineas.Count==0||input.Lineas.Any(x=>x.CantidadBase<=0)) return Results.ValidationProblem(new Dictionary<string,string[]> { ["devolucion"]=["Número, motivo y líneas con cantidades positivas son obligatorios."] });
    var result=await operations.CreateSupplierReturnAsync(empresaId,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct);return result.YaExistia?Results.Ok(result):Results.Created($"/api/v1/companies/{empresaId}/supplier-returns/{result.DocumentoId}",result);
}).RequireErpPermission("COMPRAS.DEVOLUCION.CONTABILIZAR");
app.MapGet("/api/v1/companies/{empresaId:long}/sales-returns/sources", async (long empresaId,string? q,InventoryOperationsRepository operations,CancellationToken ct) => Results.Ok(await operations.GetSalesReturnSourcesAsync(empresaId,q,ct)));
app.MapPost("/api/v1/companies/{empresaId:long}/sales-returns", async (long empresaId,CreateSalesReturnRequest input,HttpContext context,InventoryOperationsRepository operations,CancellationToken ct) =>
{
    if(string.IsNullOrWhiteSpace(input.Numero)||string.IsNullOrWhiteSpace(input.Motivo)||input.Lineas.Count==0||input.Lineas.Any(x=>x.CantidadBase<=0)) return Results.ValidationProblem(new Dictionary<string,string[]> { ["devolucion"]=["Número, motivo y líneas con cantidades positivas son obligatorios."] });
    var result=await operations.CreateSalesReturnAsync(empresaId,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct);return result.YaExistia?Results.Ok(result):Results.Created($"/api/v1/companies/{empresaId}/sales-returns/{result.DocumentoId}",result);
}).RequireErpPermission("VENTAS.DEVOLUCION.CONTABILIZAR");
app.MapPost("/api/v1/companies/{empresaId:long}/physical-counts/{id:long}/apply", async (long empresaId,long id,ApplyInventoryDocumentRequest input,HttpContext context,InventoryOperationsRepository operations,CancellationToken ct) =>
    Results.Ok(await operations.ApplyCountAsync(empresaId,id,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct))).RequireErpPermission("INVENTARIO.CONTEO.APLICAR");
app.MapPost("/api/v1/companies/{empresaId:long}/landed-cost-distributions/{id:long}/apply", async (long empresaId,long id,ApplyInventoryDocumentRequest input,HttpContext context,InventoryOperationsRepository operations,CancellationToken ct) =>
    Results.Ok(await operations.ApplyLandedCostAsync(empresaId,id,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct))).RequireErpPermission("COSTOS.DISTRIBUCION.APLICAR");
app.MapPost("/api/v1/companies/{empresaId:long}/inventory-periods/{id:long}/close", async (long empresaId,long id,CloseInventoryPeriodRequest input,HttpContext context,InventoryOperationsRepository operations,CancellationToken ct) =>
    Results.Ok(await operations.ClosePeriodAsync(empresaId,id,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct))).RequireErpPermission("INVENTARIO.PERIODO.CERRAR");
app.MapPost("/api/v1/companies/{empresaId:long}/inventory-periods/{id:long}/reopen", async (long empresaId,long id,ReopenInventoryPeriodRequest input,HttpContext context,InventoryOperationsRepository operations,CancellationToken ct) =>
    Results.Ok(await operations.ReopenPeriodAsync(empresaId,id,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct))).RequireErpPermission("INVENTARIO.PERIODO.REABRIR");

app.MapPost("/api/v1/companies/{empresaId:long}/inventory/reconcile", async (long empresaId,ReconcileInventoryRequest input,HttpContext context,InventoryOperationsRepository operations,CancellationToken ct) =>
    Results.Ok(await operations.ReconcileAsync(empresaId,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct))).RequireErpPermission("INVENTARIO.PERIODO.CERRAR");

app.MapPost("/api/v1/companies/{empresaId:long}/inventory/impairments", async (long empresaId,ImpairmentRequest input,HttpContext context,InventoryOperationsRepository operations,CancellationToken ct) =>
{
    if(input.Tipo is not ("DETERIORO" or "REVERSA") || input.ValorNetoRealizable<0 || string.IsNullOrWhiteSpace(input.Motivo) || input.Motivo.Trim().Length<10)
        return Results.ValidationProblem(new Dictionary<string,string[]> { ["deterioro"]=["Tipo, valor y motivo no son validos."] });
    return Results.Ok(await operations.RegisterImpairmentAsync(empresaId,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct));
}).RequireErpPermission("COSTOS.DETERIORO.REGISTRAR");

app.MapPost("/api/v1/companies/{empresaId:long}/inventory/negative-exceptions", async (long empresaId,RegisterNegativeInventoryRequest input,HttpContext context,InventoryOperationsRepository operations,CancellationToken ct) =>
{
    if(input.CantidadSolicitada<=0 || string.IsNullOrWhiteSpace(input.Motivo) || input.Motivo.Trim().Length<10)
        return Results.ValidationProblem(new Dictionary<string,string[]> { ["salida"]=["La cantidad debe ser positiva y el motivo debe tener al menos 10 caracteres."] });
    return Results.Ok(await operations.RegisterNegativeAsync(empresaId,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct));
}).RequireErpPermission("INVENTARIO.NEGATIVO.AUTORIZAR");

app.MapPost("/api/v1/companies/{empresaId:long}/inventory/negative-exceptions/{id:long}/regularize", async (long empresaId,long id,RegularizeNegativeInventoryRequest input,HttpContext context,InventoryOperationsRepository operations,CancellationToken ct) =>
    Results.Ok(await operations.RegularizeNegativeAsync(empresaId,id,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct))).RequireErpPermission("INVENTARIO.NEGATIVO.AUTORIZAR");

app.MapPost("/api/v1/companies/{empresaId:long}/inventory/movements/{id:long}/reverse", async (long empresaId,long id,ReverseInventoryMovementRequest input,HttpContext context,InventoryOperationsRepository operations,CancellationToken ct) =>
{
    if(string.IsNullOrWhiteSpace(input.Motivo) || input.Motivo.Trim().Length<10) return Results.ValidationProblem(new Dictionary<string,string[]> { ["motivo"]=["El motivo debe tener al menos 10 caracteres."] });
    return Results.Ok(await operations.ReverseMovementAsync(empresaId,id,input with { UsuarioId=Convert.ToInt64(context.Items["UsuarioId"]) },ct));
}).RequireErpPermission("INVENTARIO.AJUSTE.REVERSAR");

app.Run();
