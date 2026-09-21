using Microsoft.Data.SqlClient;
using NexoERP.Api.Security;
using NexoERP.Api.MasterData;
using NexoERP.Api.Data;
using System.Text.Json;

namespace NexoERP.Api.Zeus;

public static class ZeusModule
{
    public static void AddZeus(this IServiceCollection services)
    {
        services.AddScoped<ZeusRepository>();services.AddSingleton<ZeusTransport>();
        services.AddHostedService<ZeusWorker>();
    }
    public static void MapZeus(this WebApplication app)
    {
        const string admin="SEGURIDAD.PERMISOS.ADMINISTRAR";
        const string posting="COMPRAS.RECEPCION.CONTABILIZAR";
        var group=app.MapGroup("/api/v1/companies/{empresaId:long}/zeus");
        group.AddEndpointFilter(async(context,next)=>
        {
            try { return await next(context); }
            catch(ArgumentException e) { return Results.BadRequest(new {error=e.Message}); }
            catch(InvalidOperationException) { return Results.Conflict(new {error="Zeus no confirmó los datos esperados; requiere revisión."}); }
        });
        group.MapGet("/suppliers/{supplierId:long}/preview",async(long empresaId,long supplierId,ZeusRepository repo,MasterDataRepository masters,ZeusTransport transport,CancellationToken ct)=>
        {
            var supplier=(await masters.GetSuppliersAsync(empresaId,ct)).SingleOrDefault(s=>s.TerceroId==supplierId)
                ?? throw new ArgumentException("El proveedor no existe en esta empresa.");
            var settings=await repo.SettingsAsync(empresaId,ct)??throw new ArgumentException("Configura el destino y las cuentas de Zeus de esta empresa.");
            try{return Results.Ok(await transport.SupplierPreviewAsync(empresaId,settings.Configuracion,supplier,ct));}
            catch(SqlException){return Results.Json(new{error="No fue posible consultar los maestros de Zeus. Revisa la conexión privada y los permisos del usuario SQL."},statusCode:502);}
        }).RequireErpPermission(admin);
        group.MapPost("/suppliers/{supplierId:long}/send",async(long empresaId,long supplierId,ZeusSupplierSendRequest input,HttpContext http,ZeusRepository repo,MasterDataRepository masters,ZeusTransport transport,TenantConnectionFactory connections,CancellationToken ct)=>
        {
            var supplier=(await masters.GetSuppliersAsync(empresaId,ct)).SingleOrDefault(s=>s.TerceroId==supplierId)
                ?? throw new ArgumentException("El proveedor no existe en esta empresa.");
            var settings=await repo.SettingsAsync(empresaId,ct)??throw new ArgumentException("Configura el destino y las cuentas de Zeus de esta empresa.");
            if(input.Huella!=ZeusTransport.SupplierFingerprint(settings.Configuracion,supplier))throw new ArgumentException("El proveedor o la configuración de Zeus cambió. Cierra y consulta de nuevo antes de enviar.");
            var attempt=Guid.NewGuid();
            async Task Audit(string operation,object details,CancellationToken token){
                await using var c=await connections.OpenAsync(empresaId,false,token);
                await using var q=ZeusRepository.Command(c,"INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@E,@U,@Op,'ter.Tercero',@Id,@J,'ZEUS')",empresaId);
                ZeusRepository.Add(q,"@U",Convert.ToInt64(http.Items["UsuarioId"]));ZeusRepository.Add(q,"@Op",operation);ZeusRepository.Add(q,"@Id",supplierId.ToString());ZeusRepository.Add(q,"@J",JsonSerializer.Serialize(new{intento=attempt,datos=details}));
                await q.ExecuteNonQueryAsync(token);
            }
            await Audit("ZEUS_PROVEEDOR_SOLICITAR",new{proveedor=supplier.NumeroIdentificacion,destino=settings.Configuracion.BaseEsperada,parametros=input},ct);
            ZeusSupplierSendResult result;
            try{result=await transport.SendSupplierAsync(empresaId,settings.Configuracion,supplier,input,ct);}
            catch(SqlException){result=new("RECHAZADO",supplier.NumeroIdentificacion,"No se pudo abrir la conexión de Zeus. Revisa la conexión privada y los permisos.");}
            catch(ArgumentException e){result=new("RECHAZADO",supplier.NumeroIdentificacion,e.Message);}
            using var auditTimeout=new CancellationTokenSource(TimeSpan.FromSeconds(15));
            try{await Audit("ZEUS_PROVEEDOR_RESULTADO",result,auditTimeout.Token);}
            catch(Exception e) when(e is SqlException or OperationCanceledException){
                result=result with{Mensaje=result.Mensaje+" No fue posible registrar la auditoría final en el ERP; conserva este resultado y consulta el proveedor antes de repetir."};
            }
            return Results.Ok(result);
        }).RequireErpPermission(admin);
        group.MapGet("/configuration",async(long empresaId,ZeusRepository repo,CancellationToken ct)=>
        {
            var result=await repo.SettingsAsync(empresaId,ct);
            return result is null?Results.NotFound():Results.Ok(result);
        }).RequireErpPermission(admin);
        group.MapPut("/configuration",async(long empresaId,ZeusSettingsRequest input,HttpContext http,ZeusRepository repo,CancellationToken ct)=>
        {
            await repo.SaveSettingsAsync(empresaId,Convert.ToInt64(http.Items["UsuarioId"]),input,ct);return Results.NoContent();
        }).RequireErpPermission(admin);
        group.MapGet("/concepts",()=>Results.Ok(ZeusJournal.Concepts)).RequireErpPermission(admin);
        group.MapGet("/status",async(long empresaId,HttpContext http,AuthRepository auth,ZeusRepository repo,IConfiguration config,CancellationToken ct)=>
        {
            var user=Convert.ToInt64(http.Items["UsuarioId"]);
            if(!await auth.HasPermissionAsync(user,empresaId,admin,ct)&&!await auth.HasPermissionAsync(user,empresaId,posting,ct))return Results.StatusCode(403);
            var settings=await repo.SettingsAsync(empresaId,ct);
            return Results.Ok(new {configurado=settings is not null,habilitado=settings?.Configuracion.Habilitado??false,despachadorActivo=config.GetValue<bool>("Zeus:Enabled")});
        });
        group.MapGet("/receipts",async(long empresaId,string? q,ZeusRepository repo,CancellationToken ct)=>Results.Ok(await repo.ReceiptsAsync(empresaId,q,ct))).RequireErpPermission(posting);
        group.MapPost("/connection/check",async(long empresaId,ZeusRepository repo,ZeusTransport transport,CancellationToken ct)=>
        {
            var settings=await repo.SettingsAsync(empresaId,ct) ?? throw new ArgumentException("Configura primero la empresa.");
            try { return Results.Ok(await transport.CheckAsync(empresaId,settings.Configuracion,ct)); }
            catch(SqlException) { return Results.Json(new {error="No se pudo verificar la conexión o el contrato de Zeus."},statusCode:502); }
        }).RequireErpPermission(admin);
        group.MapPost("/receipts/{receiptId:long}/preview",async(long empresaId,long receiptId,ZeusPreviewRequest input,ZeusRepository repo,CancellationToken ct)=>
            Results.Ok(await repo.PreviewAsync(empresaId,receiptId,input,ct))).RequireErpPermission(posting);
        group.MapPost("/receipts/{receiptId:long}/approve",async(long empresaId,long receiptId,ZeusApproveRequest input,HttpContext http,ZeusRepository repo,CancellationToken ct)=>
        {
            var id=await repo.ApproveAsync(empresaId,receiptId,Convert.ToInt64(http.Items["UsuarioId"]),input,ct);
            return Results.Accepted($"/api/v1/companies/{empresaId}/zeus/jobs",new {envioId=id});
        }).RequireErpPermission(posting);
        group.MapGet("/jobs",async(long empresaId,string? estado,int? offset,ZeusRepository repo,CancellationToken ct)=>
            Results.Ok(await repo.ListAsync(empresaId,estado,offset??0,ct))).RequireErpPermission(posting);
        group.MapPost("/jobs/{id:long}/reconcile",async(long empresaId,long id,ZeusRepository repo,ZeusTransport transport,CancellationToken ct)=>
        {
            var job=await repo.UncertainAsync(empresaId,id,ct);
            try
            {
                var result=await transport.ReconcileAsync(empresaId,job.Snapshot,job.Key,ct);
                if(result.Estado=="CONTABILIZADO") await repo.FinishAsync(empresaId,id,result.Estado,result.Fuente,result.Documento,null,ct);
                return Results.Ok(result);
            }
            catch(SqlException) { return Results.Json(new {error="No se pudo conciliar con Zeus; el envío conserva su estado incierto."},statusCode:502); }
        }).RequireErpPermission(admin);
    }
}

public sealed class ZeusWorker(IServiceScopeFactory scopes,IConfiguration configuration,ILogger<ZeusWorker> logger):BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while(!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if(configuration.GetValue<bool>("Zeus:Enabled"))
                {
                    using var scope=scopes.CreateScope();var repo=scope.ServiceProvider.GetRequiredService<ZeusRepository>();
                    var job=await repo.ClaimAsync(stoppingToken);
                    if(job is not null)
                    {
                        var j=job.Value;
                        using var deadline=CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);deadline.CancelAfter(TimeSpan.FromMinutes(3));
                        var result=await repo.EligibleAsync(j.Company,j.Snapshot,deadline.Token)
                            ? await scope.ServiceProvider.GetRequiredService<ZeusTransport>().SendAsync(j.Company,j.Snapshot,j.Key,deadline.Token)
                            : new ZeusResult("RECHAZADO",Error:"La entrada o su configuración cambiaron. Genera y revisa una nueva vista previa.");
                        using var finish=new CancellationTokenSource(TimeSpan.FromSeconds(15));
                        await repo.FinishAsync(j.Company,j.Id,result.Estado,result.Fuente,result.Documento,result.Error,finish.Token);
                    }
                }
            }
            catch(OperationCanceledException) when(stoppingToken.IsCancellationRequested) { break; }
            catch(Exception e) { logger.LogWarning("El despachador Zeus requiere revisión ({Type}). Los envíos interrumpidos no se reenvían automáticamente.",e.GetType().Name); }
            try { await Task.Delay(TimeSpan.FromSeconds(10),stoppingToken); }
            catch(OperationCanceledException) { break; }
        }
    }
}
