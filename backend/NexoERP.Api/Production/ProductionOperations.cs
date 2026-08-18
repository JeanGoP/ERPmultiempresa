using System.Data;
using System.Diagnostics;
using System.Net.Http.Headers;
using System.Text;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Options;
using NexoERP.Api.Data;

namespace NexoERP.Api.Production;

public sealed class OutboxOptions
{
    public bool Enabled { get; set; } = true;
    public int BatchSize { get; set; } = 25;
    public int PollSeconds { get; set; } = 2;
    public int MaxAttempts { get; set; } = 8;
    public string DeliveryMode { get; set; } = "Ledger";
    public string? WebhookUrl { get; set; }
}

public sealed record OutboxMessage(long OutboxEventoId,long EmpresaId,Guid EventoGuid,string TipoEvento,string TipoAgregado,string AgregadoId,string Payload,int Intentos);
public sealed record PlatformHealth(int Migrations,long PendingOutbox,long DiscardedOutbox,DateTime? OldestPendingUtc);
public sealed record CompanyOperationsStatus(long PendingOutbox,long DiscardedOutbox,long Deliveries24Hours,long ActiveAlerts,DateTime? LastDeliveryUtc);
public sealed record OperationAlert(long AlertaOperacionId,string Severidad,string Codigo,string Mensaje,string? Entidad,string? EntidadId,DateTime CreadaEnUtc);
public sealed record RuntimeMetrics(long Requests,long Errors,double AverageMilliseconds,long OutboxDelivered,long OutboxFailed,DateTime StartedAtUtc);

public sealed class OperationalMetrics
{
    private long _requests,_errors,_elapsedTicks,_outboxDelivered,_outboxFailed;
    private readonly DateTime _startedAtUtc=DateTime.UtcNow;
    public void RecordRequest(TimeSpan elapsed,bool error){Interlocked.Increment(ref _requests);Interlocked.Add(ref _elapsedTicks,elapsed.Ticks);if(error)Interlocked.Increment(ref _errors);}
    public void RecordOutbox(bool success){Interlocked.Increment(ref success?ref _outboxDelivered:ref _outboxFailed);}
    public RuntimeMetrics Snapshot(){var requests=Interlocked.Read(ref _requests);return new(requests,Interlocked.Read(ref _errors),requests==0?0:TimeSpan.FromTicks(Interlocked.Read(ref _elapsedTicks)/requests).TotalMilliseconds,Interlocked.Read(ref _outboxDelivered),Interlocked.Read(ref _outboxFailed),_startedAtUtc);}
}

public sealed class ProductionOperationsRepository(TenantConnectionFactory connections)
{
    private static void Add(SqlCommand command,string name,SqlDbType type,object? value,int size=0){var p=command.Parameters.Add(name,type,size);p.Value=value??DBNull.Value;}

    public async Task<IReadOnlyList<OutboxMessage>> ClaimAsync(string worker,int batch,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(null,true,ct);await using var q=c.CreateCommand();q.CommandType=CommandType.StoredProcedure;q.CommandText="core.usp_ReclamarOutbox";Add(q,"@Trabajador",SqlDbType.NVarChar,worker,100);Add(q,"@TamanoLote",SqlDbType.Int,batch);Add(q,"@SegundosBloqueo",SqlDbType.Int,60);
        await using var r=await q.ExecuteReaderAsync(ct);var rows=new List<OutboxMessage>();while(await r.ReadAsync(ct))rows.Add(new(r.GetInt64(0),r.GetInt64(1),r.GetGuid(2),r.GetString(3),r.GetString(4),r.GetString(5),r.GetString(6),r.GetInt32(7)));return rows;
    }
    public async Task CompleteAsync(long id,string worker,string destination,string? response,CancellationToken ct){await using var c=await connections.OpenAsync(null,true,ct);await using var q=c.CreateCommand();q.CommandType=CommandType.StoredProcedure;q.CommandText="core.usp_ConfirmarOutbox";Add(q,"@OutboxEventoId",SqlDbType.BigInt,id);Add(q,"@Trabajador",SqlDbType.NVarChar,worker,100);Add(q,"@Destino",SqlDbType.NVarChar,destination,100);Add(q,"@Respuesta",SqlDbType.NVarChar,response,1000);await q.ExecuteNonQueryAsync(ct);}
    public async Task FailAsync(long id,string worker,string error,int maxAttempts,CancellationToken ct){await using var c=await connections.OpenAsync(null,true,ct);await using var q=c.CreateCommand();q.CommandType=CommandType.StoredProcedure;q.CommandText="core.usp_FallarOutbox";Add(q,"@OutboxEventoId",SqlDbType.BigInt,id);Add(q,"@Trabajador",SqlDbType.NVarChar,worker,100);Add(q,"@Error",SqlDbType.NVarChar,error,2000);Add(q,"@MaximoIntentos",SqlDbType.Int,maxAttempts);await q.ExecuteNonQueryAsync(ct);}
    public async Task<PlatformHealth> GetPlatformHealthAsync(CancellationToken ct){await using var c=await connections.OpenAsync(null,true,ct);await using var q=c.CreateCommand();q.CommandText="SELECT (SELECT COUNT(*) FROM core.SchemaMigration),(SELECT COUNT_BIG(*) FROM core.OutboxEvento WHERE ProcesadoEnUtc IS NULL AND DescartadoEnUtc IS NULL),(SELECT COUNT_BIG(*) FROM core.OutboxEvento WHERE DescartadoEnUtc IS NOT NULL),(SELECT MIN(OcurridoEnUtc) FROM core.OutboxEvento WHERE ProcesadoEnUtc IS NULL AND DescartadoEnUtc IS NULL);";await using var r=await q.ExecuteReaderAsync(ct);await r.ReadAsync(ct);return new(r.GetInt32(0),r.GetInt64(1),r.GetInt64(2),r.IsDBNull(3)?null:r.GetDateTime(3));}
    public async Task<CompanyOperationsStatus> GetCompanyStatusAsync(long companyId,CancellationToken ct){await using var c=await connections.OpenAsync(companyId,false,ct);await using var q=c.CreateCommand();q.CommandText="SELECT (SELECT COUNT_BIG(*) FROM core.OutboxEvento WHERE EmpresaId=@E AND ProcesadoEnUtc IS NULL AND DescartadoEnUtc IS NULL),(SELECT COUNT_BIG(*) FROM core.OutboxEvento WHERE EmpresaId=@E AND DescartadoEnUtc IS NOT NULL),(SELECT COUNT_BIG(*) FROM core.EntregaIntegracion WHERE EmpresaId=@E AND EntregadoEnUtc>=DATEADD(HOUR,-24,SYSUTCDATETIME())),(SELECT COUNT_BIG(*) FROM core.AlertaOperacion WHERE EmpresaId=@E AND ResueltaEnUtc IS NULL),(SELECT MAX(EntregadoEnUtc) FROM core.EntregaIntegracion WHERE EmpresaId=@E);";Add(q,"@E",SqlDbType.BigInt,companyId);await using var r=await q.ExecuteReaderAsync(ct);await r.ReadAsync(ct);return new(r.GetInt64(0),r.GetInt64(1),r.GetInt64(2),r.GetInt64(3),r.IsDBNull(4)?null:r.GetDateTime(4));}
    public async Task<IReadOnlyList<OperationAlert>> GetAlertsAsync(long companyId,CancellationToken ct){await using var c=await connections.OpenAsync(companyId,false,ct);await using var q=c.CreateCommand();q.CommandText="SELECT TOP(100) AlertaOperacionId,Severidad,Codigo,Mensaje,Entidad,EntidadId,CreadaEnUtc FROM core.AlertaOperacion WHERE EmpresaId=@E AND ResueltaEnUtc IS NULL ORDER BY CASE Severidad WHEN 'CRITICAL' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END,CreadaEnUtc DESC;";Add(q,"@E",SqlDbType.BigInt,companyId);await using var r=await q.ExecuteReaderAsync(ct);var rows=new List<OperationAlert>();while(await r.ReadAsync(ct))rows.Add(new(r.GetInt64(0),r.GetString(1),r.GetString(2),r.GetString(3),r.IsDBNull(4)?null:r.GetString(4),r.IsDBNull(5)?null:r.GetString(5),r.GetDateTime(6)));return rows;}
    public async Task RetryAsync(long companyId,long eventId,CancellationToken ct){await using var c=await connections.OpenAsync(companyId,false,ct);await using var q=c.CreateCommand();q.CommandType=CommandType.StoredProcedure;q.CommandText="core.usp_ReintentarOutbox";Add(q,"@EmpresaId",SqlDbType.BigInt,companyId);Add(q,"@OutboxEventoId",SqlDbType.BigInt,eventId);await q.ExecuteNonQueryAsync(ct);}
}

public sealed class OutboxDispatcherService(ProductionOperationsRepository repository,IHttpClientFactory clients,IOptions<OutboxOptions> configured,OperationalMetrics metrics,ILogger<OutboxDispatcherService> logger) : BackgroundService
{
    private readonly OutboxOptions _options=configured.Value;
    private readonly string _worker=$"{Environment.MachineName}:{Environment.ProcessId}:{Guid.NewGuid():N}";
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if(!_options.Enabled){logger.LogWarning("Consumidor Outbox deshabilitado por configuración.");return;}
        while(!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var batch=await repository.ClaimAsync(_worker,_options.BatchSize,stoppingToken);
                if(batch.Count==0){await Task.Delay(TimeSpan.FromSeconds(Math.Max(1,_options.PollSeconds)),stoppingToken);continue;}
                foreach(var message in batch)await DispatchAsync(message,stoppingToken);
            }
            catch(OperationCanceledException) when(stoppingToken.IsCancellationRequested){break;}
            catch(Exception error){logger.LogError(error,"Fallo general del consumidor Outbox.");await Task.Delay(TimeSpan.FromSeconds(5),stoppingToken);}
        }
    }
    private async Task DispatchAsync(OutboxMessage message,CancellationToken ct)
    {
        try
        {
            var destination="LEDGER_INTERNO";string response="Entrega registrada idempotentemente en SQL Server.";
            if(string.Equals(_options.DeliveryMode,"Webhook",StringComparison.OrdinalIgnoreCase))
            {
                if(!Uri.TryCreate(_options.WebhookUrl,UriKind.Absolute,out var endpoint))throw new InvalidOperationException("Outbox:WebhookUrl no es una URL absoluta válida.");
                using var request=new HttpRequestMessage(HttpMethod.Post,endpoint){Content=new StringContent(message.Payload,Encoding.UTF8,"application/json")};
                request.Headers.TryAddWithoutValidation("Idempotency-Key",message.EventoGuid.ToString());request.Headers.TryAddWithoutValidation("X-Nexo-Event-Type",message.TipoEvento);request.Headers.TryAddWithoutValidation("X-Nexo-Company-Id",message.EmpresaId.ToString());request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
                using var result=await clients.CreateClient(nameof(OutboxDispatcherService)).SendAsync(request,ct);response=$"HTTP {(int)result.StatusCode}";result.EnsureSuccessStatusCode();destination="WEBHOOK_CONTABLE";
            }
            await repository.CompleteAsync(message.OutboxEventoId,_worker,destination,response,ct);metrics.RecordOutbox(true);logger.LogInformation("Outbox {EventId} {EventType} entregado a {Destination}.",message.OutboxEventoId,message.TipoEvento,destination);
        }
        catch(Exception error)
        {
            metrics.RecordOutbox(false);logger.LogError(error,"Falló entrega Outbox {EventId}, intento {Attempt}.",message.OutboxEventoId,message.Intentos);
            await repository.FailAsync(message.OutboxEventoId,_worker,error.Message,_options.MaxAttempts,ct);
        }
    }
}
