using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;
using NexoERP.Api.Zeus;

namespace NexoERP.Api.Sales;

public sealed class CustomerZeusWorker(IServiceScopeFactory scopes,ILogger<CustomerZeusWorker> logger):BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while(!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope=scopes.CreateScope();
                var connections=scope.ServiceProvider.GetRequiredService<TenantConnectionFactory>();
                await using var c=await connections.OpenAsync(null,true,stoppingToken);
                await using(var cleanup=c.CreateCommand())
                {
                    cleanup.CommandText="""
                    UPDATE ven.ClientePerfil SET ZeusEstado='INCIERTO',ZeusMensaje=N'Envío interrumpido; verifica el tercero en Zeus antes de reintentar.',ZeusActualizadoEnUtc=SYSUTCDATETIME()
                    WHERE ZeusEstado='ENVIANDO' AND ZeusActualizadoEnUtc<DATEADD(minute,-10,SYSUTCDATETIME());
                    """;
                    await cleanup.ExecuteNonQueryAsync(stoppingToken);
                }
                await using var q=c.CreateCommand();q.CommandText="""
                    ;WITH siguiente AS(SELECT TOP(1) * FROM ven.ClientePerfil WITH(UPDLOCK,READPAST,READCOMMITTEDLOCK)
                        WHERE ZeusEstado='PENDIENTE' ORDER BY ZeusActualizadoEnUtc)
                    UPDATE siguiente SET ZeusEstado='ENVIANDO',ZeusIntentos=ZeusIntentos+1,ZeusIntento=NEWID(),
                        ZeusActualizadoEnUtc=SYSUTCDATETIME(),ZeusMensaje=N'Verificando tercero en Zeus.'
                    OUTPUT inserted.EmpresaId,inserted.TerceroId,inserted.ZeusIntento;
                    """;
                long company,id;Guid attempt;
                await using(var r=await q.ExecuteReaderAsync(stoppingToken))
                {
                    if(!await r.ReadAsync(stoppingToken))
                    {await Task.Delay(TimeSpan.FromSeconds(5),stoppingToken);continue;}
                    company=r.GetInt64(0);id=r.GetInt64(1);attempt=r.GetGuid(2);
                }
                var customers=scope.ServiceProvider.GetRequiredService<CustomerRepository>();
                var transport=scope.ServiceProvider.GetRequiredService<ZeusTransport>();
                var settings=scope.ServiceProvider.GetRequiredService<ZeusRepository>();
                ZeusCustomerResult result;
                try
                {
                    using var deadline=CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
                    deadline.CancelAfter(TimeSpan.FromMinutes(3));
                    var customer=(await customers.ListAsync(company,deadline.Token)).Single(x=>x.TerceroId==id);
                    var config=await settings.SettingsAsync(company,deadline.Token);
                    result=config is null?new("RECHAZADO","Configura la conexión Zeus de la empresa."):
                        await transport.EnsureCustomerThirdAsync(company,config.Configuracion,customer,deadline.Token);
                }
                catch(Exception e) when(e is SqlException or ArgumentException or InvalidOperationException or OperationCanceledException)
                {result=new(e is OperationCanceledException?"INCIERTO":"RECHAZADO",e is SqlException?"No se pudo consultar Zeus o el ERP; revisa conexión y permisos.":e.Message);}
                await using var finish=await connections.OpenAsync(company,false,CancellationToken.None);
                await using var update=finish.CreateCommand();update.CommandText="""
                    UPDATE ven.ClientePerfil SET ZeusEstado=@State,ZeusMensaje=@Message,ZeusActualizadoEnUtc=SYSUTCDATETIME()
                    WHERE EmpresaId=@E AND TerceroId=@Id AND ZeusIntento=@Attempt AND ZeusEstado='ENVIANDO';
                    """;
                update.Parameters.AddWithValue("@E",company);update.Parameters.AddWithValue("@Id",id);
                update.Parameters.AddWithValue("@Attempt",attempt);update.Parameters.AddWithValue("@State",result.Estado);
                update.Parameters.AddWithValue("@Message",result.Mensaje[..Math.Min(1500,result.Mensaje.Length)]);
                await update.ExecuteNonQueryAsync(CancellationToken.None);
            }
            catch(OperationCanceledException) when(stoppingToken.IsCancellationRequested){break;}
            catch(Exception e){logger.LogWarning("No se completó el ciclo de clientes Zeus ({Tipo}).",e.GetType().Name);}
            try{await Task.Delay(TimeSpan.FromSeconds(5),stoppingToken);}catch(OperationCanceledException){break;}
        }
    }
}
