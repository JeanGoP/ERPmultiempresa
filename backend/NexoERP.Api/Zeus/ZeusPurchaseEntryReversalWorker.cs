using NexoERP.Api.Purchasing;

namespace NexoERP.Api.Zeus;

public sealed class ZeusPurchaseEntryReversalWorker(IServiceScopeFactory scopes,IConfiguration configuration,
    ILogger<ZeusPurchaseEntryReversalWorker> logger):BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while(!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if(configuration.GetValue<bool>("Zeus:Enabled"))
                {
                    using var scope=scopes.CreateScope();
                    var repository=scope.ServiceProvider.GetRequiredService<PurchaseEntryReversalRepository>();
                    var job=await repository.ClaimAsync(stoppingToken);
                    if(job is not null)
                    {
                        using var deadline=CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
                        deadline.CancelAfter(TimeSpan.FromMinutes(3));
                        var settings=await scope.ServiceProvider.GetRequiredService<ZeusRepository>().SettingsAsync(job.Company,deadline.Token);
                        var result=settings?.Configuracion.Habilitado==true
                            ?await scope.ServiceProvider.GetRequiredService<ZeusTransport>().SendAsync(job.Company,job.Snapshot,job.Key,deadline.Token)
                            :new ZeusResult("RECHAZADO",Error:"Activa la integración Zeus de esta empresa y reintenta la reversión de entrada.");
                        using var finish=new CancellationTokenSource(TimeSpan.FromSeconds(15));
                        await repository.FinishAsync(job,result,finish.Token);
                    }
                }
            }
            catch(OperationCanceledException)when(stoppingToken.IsCancellationRequested){break;}
            catch(Exception error){logger.LogWarning("La reversión de entradas a Zeus requiere revisión ({Type}).",error.GetType().Name);}
            try{await Task.Delay(TimeSpan.FromSeconds(10),stoppingToken);}
            catch(OperationCanceledException){break;}
        }
    }
}
