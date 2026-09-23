using System.Text.Json;
using NexoERP.Api.Data;
using NexoERP.Api.Zeus;
using NexoERP.Api.Security;

namespace NexoERP.Api.Treasury;
public sealed class DisbursementQueue(TenantConnectionFactory connections)
{
    public async Task<(long Id,long Company,Guid Key,ZeusSnapshot Snapshot)?> ClaimAsync(CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(null,true,ct);await using var q=c.CreateCommand();
        q.CommandText="""
            UPDATE cxp.Egreso SET ZeusEstado='INCIERTO',ZeusError=N'Envío interrumpido. Concilia antes de reenviar.',ActualizadoEnUtc=SYSUTCDATETIME() WHERE ZeusEstado='ENVIANDO' AND ActualizadoEnUtc<DATEADD(minute,-10,SYSUTCDATETIME());
            DECLARE @Claim TABLE(Id bigint,EmpresaId bigint,Clave uniqueidentifier,Snapshot nvarchar(max));
            ;WITH next AS(SELECT TOP(1) * FROM cxp.Egreso WITH(UPDLOCK,ROWLOCK) WHERE ZeusEstado='PENDIENTE' ORDER BY EgresoId)
            UPDATE next SET ZeusEstado='ENVIANDO',Intentos=Intentos+1,ActualizadoEnUtc=SYSUTCDATETIME()
            OUTPUT inserted.EgresoId,inserted.EmpresaId,inserted.OperacionGuid,inserted.Snapshot INTO @Claim;
            SELECT Id,EmpresaId,Clave,Snapshot FROM @Claim;
            """;
        await using var r=await q.ExecuteReaderAsync(ct);return await r.ReadAsync(ct)?(r.GetInt64(0),r.GetInt64(1),r.GetGuid(2),JsonSerializer.Deserialize<ZeusSnapshot>(r.GetString(3))!):null;
    }
    public async Task FinishAsync(long company,long id,ZeusResult result,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);await using var q=ZeusRepository.Command(c,"""
            SET XACT_ABORT ON;
            BEGIN TRANSACTION;
            UPDATE cxp.Egreso SET ZeusEstado=@State,ZeusFuente=@F,ZeusDocumento=@N,ZeusError=@Error,ActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E AND EgresoId=@Id AND ZeusEstado IN('ENVIANDO','INCIERTO');
            IF @@ROWCOUNT=1 INSERT audit.Evento(EmpresaId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
                VALUES(@E,'RESULTADO_EGRESO_ZEUS','cxp.Egreso',CONVERT(varchar(30),@Id),@Result,'ZEUS');
            COMMIT;
            """,company);
        ZeusRepository.Add(q,"@Result",JsonSerializer.Serialize(result));
        foreach(var p in new (string,object?)[]{("@State",result.Estado),("@F",result.Fuente),("@N",result.Documento),("@Error",result.Error),("@Id",id)})q.Parameters.AddWithValue(p.Item1,p.Item2??DBNull.Value);
        await q.ExecuteNonQueryAsync(ct);
    }
    public async Task RetryAsync(long company,long id,long user,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);await using var tx=(Microsoft.Data.SqlClient.SqlTransaction)await c.BeginTransactionAsync(ct);
        await using var q=ZeusRepository.Command(c,"""
            UPDATE cxp.Egreso SET ZeusEstado='PENDIENTE',ZeusError=NULL,ActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E AND EgresoId=@Id AND ZeusEstado='RECHAZADO';
            IF @@ROWCOUNT<>1 THROW 52114,'Solo se reenvían rechazos confirmados; los inciertos requieren conciliación.',1;
            INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,AplicacionOrigen) VALUES(@E,@U,'REENVIAR_EGRESO_ZEUS','cxp.Egreso',CONVERT(varchar(30),@Id),'ERP');
            """,company,tx);ZeusRepository.Add(q,"@Id",id);ZeusRepository.Add(q,"@U",user);await q.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);
    }
    public async Task<ZeusResult> ReconcileAsync(long company,long id,ZeusTransport transport,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);await using var q=ZeusRepository.Command(c,"SELECT OperacionGuid,Snapshot FROM cxp.Egreso WHERE EmpresaId=@E AND EgresoId=@Id AND ZeusEstado='INCIERTO'",company);ZeusRepository.Add(q,"@Id",id);
        Guid key;ZeusSnapshot snapshot;
        await using(var r=await q.ExecuteReaderAsync(ct)){if(!await r.ReadAsync(ct))throw new ArgumentException("El egreso no está en estado incierto.");key=r.GetGuid(0);snapshot=JsonSerializer.Deserialize<ZeusSnapshot>(r.GetString(1))!;}
        var result=await transport.ReconcileAsync(company,snapshot,key,ct);if(result.Estado=="CONTABILIZADO")await FinishAsync(company,id,result,ct);return result;
    }
}
public sealed class DisbursementWorker(IServiceScopeFactory scopes,IConfiguration configuration,ILogger<DisbursementWorker> logger):BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        while(!ct.IsCancellationRequested)
        {
            try
            {
                if(configuration.GetValue<bool>("Zeus:Enabled"))
                {
                    using var scope=scopes.CreateScope();var queue=scope.ServiceProvider.GetRequiredService<DisbursementQueue>();var job=await queue.ClaimAsync(ct);
                    if(job is { } j)
                    {
                        using var deadline=CancellationTokenSource.CreateLinkedTokenSource(ct);deadline.CancelAfter(TimeSpan.FromMinutes(3));
                        var current=await scope.ServiceProvider.GetRequiredService<ZeusRepository>().SettingsAsync(j.Company,deadline.Token);
                        var result=current?.Configuracion.Habilitado==true&&current.Configuracion.ServidorEsperado==j.Snapshot.Configuracion.ServidorEsperado&&current.Configuracion.BaseEsperada==j.Snapshot.Configuracion.BaseEsperada
                            ?await scope.ServiceProvider.GetRequiredService<ZeusTransport>().SendAsync(j.Company,j.Snapshot,j.Key,deadline.Token)
                            :new ZeusResult("RECHAZADO",Error:"Integración deshabilitada o destino Zeus modificado; no se envió el egreso.");
                        using var finish=new CancellationTokenSource(TimeSpan.FromSeconds(15));await queue.FinishAsync(j.Company,j.Id,result,finish.Token);
                    }
                }
            }
            catch(OperationCanceledException)when(ct.IsCancellationRequested){break;}
            catch(Exception e){logger.LogWarning("Envío de egreso requiere revisión ({Type}); no se repite el pago.",e.GetType().Name);}
            try{await Task.Delay(TimeSpan.FromSeconds(10),ct);}catch(OperationCanceledException){break;}
        }
    }
}
