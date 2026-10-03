using System.Text.Json;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;
using NexoERP.Api.Zeus;

namespace NexoERP.Api.Sales;

public sealed record CustomerPostingJob(string Tipo,long Id,long EmpresaId,Guid Clave,ZeusSnapshot Snapshot);

public sealed class CustomerPostingQueue(TenantConnectionFactory connections)
{
    public async Task<CustomerPostingJob?> ClaimAsync(CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(null,true,ct);
        await using var q=c.CreateCommand();q.CommandText="""
            UPDATE ven.FacturaVenta SET ZeusEstado='INCIERTO',ZeusError=N'Envío interrumpido. Conciliar en Zeus antes de reintentar.',ZeusActualizadoEnUtc=SYSUTCDATETIME()
            WHERE ZeusEstado='ENVIANDO' AND ZeusActualizadoEnUtc<DATEADD(minute,-10,SYSUTCDATETIME());
            UPDATE cxc.ReciboCaja SET ZeusEstado='INCIERTO',ZeusError=N'Envío interrumpido. Conciliar en Zeus antes de reintentar.',ZeusActualizadoEnUtc=SYSUTCDATETIME()
            WHERE ZeusEstado='ENVIANDO' AND ZeusActualizadoEnUtc<DATEADD(minute,-10,SYSUTCDATETIME());
            DECLARE @Claim TABLE(Tipo varchar(10),Id bigint,EmpresaId bigint,Clave uniqueidentifier,Snapshot nvarchar(max));
            ;WITH next AS(SELECT TOP(1) * FROM ven.FacturaVenta WITH(UPDLOCK,ROWLOCK)
                WHERE ZeusEstado='PENDIENTE' AND Snapshot IS NOT NULL ORDER BY FacturaVentaId)
            UPDATE next SET ZeusEstado='ENVIANDO',ZeusIntentos=ZeusIntentos+1,ZeusActualizadoEnUtc=SYSUTCDATETIME()
            OUTPUT 'FACTURA',inserted.FacturaVentaId,inserted.EmpresaId,inserted.OperacionGuid,inserted.Snapshot INTO @Claim;
            IF NOT EXISTS(SELECT 1 FROM @Claim)
            BEGIN
                ;WITH next AS(SELECT TOP(1) * FROM cxc.ReciboCaja WITH(UPDLOCK,ROWLOCK)
                    WHERE ZeusEstado='PENDIENTE' AND Snapshot IS NOT NULL ORDER BY ReciboCajaId)
                UPDATE next SET ZeusEstado='ENVIANDO',ZeusIntentos=ZeusIntentos+1,ZeusActualizadoEnUtc=SYSUTCDATETIME()
                OUTPUT 'RECIBO',inserted.ReciboCajaId,inserted.EmpresaId,inserted.OperacionGuid,inserted.Snapshot INTO @Claim;
            END;
            SELECT Tipo,Id,EmpresaId,Clave,Snapshot FROM @Claim;
            """;
        await using var r=await q.ExecuteReaderAsync(ct);
        return await r.ReadAsync(ct)?new(r.GetString(0),r.GetInt64(1),r.GetInt64(2),r.GetGuid(3),JsonSerializer.Deserialize<ZeusSnapshot>(r.GetString(4))!):null;
    }
    public async Task FinishAsync(CustomerPostingJob job,ZeusResult result,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(job.EmpresaId,false,ct);
        var table=job.Tipo=="FACTURA"?"ven.FacturaVenta":"cxc.ReciboCaja";
        var key=job.Tipo=="FACTURA"?"FacturaVentaId":"ReciboCajaId";
        await using var q=ZeusRepository.Command(c,$"UPDATE {table} SET ZeusEstado=@State,ZeusFuente=@F,ZeusDocumento=@N,ZeusError=@Error,ZeusActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E AND {key}=@Id AND ZeusEstado IN('ENVIANDO','INCIERTO')",job.EmpresaId);
        ZeusRepository.Add(q,"@Id",job.Id);ZeusRepository.Add(q,"@State",result.Estado);
        q.Parameters.AddWithValue("@F",(object?)result.Fuente??DBNull.Value);q.Parameters.AddWithValue("@N",(object?)result.Documento??DBNull.Value);
        q.Parameters.AddWithValue("@Error",(object?)result.Error??DBNull.Value);
        await q.ExecuteNonQueryAsync(ct);
    }
    public async Task RetryAsync(long company,string type,long id,CancellationToken ct)
    {
        var (table,key)=Table(type);
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,$"UPDATE {table} SET ZeusEstado='PENDIENTE',ZeusError=NULL,ZeusActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E AND {key}=@Id AND ZeusEstado='RECHAZADO'",company);
        ZeusRepository.Add(q,"@Id",id);
        if(await q.ExecuteNonQueryAsync(ct)!=1)throw new ArgumentException("Solo se reenvían rechazos confirmados. Los inciertos se concilian.");
    }
    public async Task MarkCustomerCreatedAsync(long company,long customerId,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"UPDATE ven.ClientePerfil SET ZeusEstado='CLIENTE',ZeusMensaje=N'Cliente confirmado en Zeus al emitir la primera factura.',ZeusActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E AND TerceroId=@Id AND ZeusEstado IN('TERCERO','CLIENTE')",company);
        ZeusRepository.Add(q,"@Id",customerId);await q.ExecuteNonQueryAsync(ct);
    }
    public async Task<ZeusResult> ReconcileAsync(long company,string type,long id,ZeusTransport transport,CancellationToken ct)
    {
        var (table,key)=Table(type);
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,$"SELECT OperacionGuid,Snapshot FROM {table} WHERE EmpresaId=@E AND {key}=@Id AND ZeusEstado='INCIERTO'",company);
        ZeusRepository.Add(q,"@Id",id);Guid operation;ZeusSnapshot snapshot;
        await using(var r=await q.ExecuteReaderAsync(ct))
        {
            if(!await r.ReadAsync(ct)||r.IsDBNull(1))throw new ArgumentException("El documento no está en estado incierto.");
            operation=r.GetGuid(0);snapshot=JsonSerializer.Deserialize<ZeusSnapshot>(r.GetString(1))!;
        }
        var result=await transport.ReconcileAsync(company,snapshot,operation,ct);
        if(result.Estado=="CONTABILIZADO")await FinishAsync(new(type,id,company,operation,snapshot),result,ct);
        return result;
    }
    private static (string Table,string Key) Table(string type)=>type switch
    {
        "FACTURA"=>("ven.FacturaVenta","FacturaVentaId"),
        "RECIBO"=>("cxc.ReciboCaja","ReciboCajaId"),
        _=>throw new ArgumentException("Tipo de documento no válido.")
    };
}

public sealed class CustomerPostingWorker(IServiceScopeFactory scopes,IConfiguration configuration,ILogger<CustomerPostingWorker> logger):BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        while(!ct.IsCancellationRequested)
        {
            try
            {
                if(configuration.GetValue<bool>("Zeus:Enabled"))
                {
                    using var scope=scopes.CreateScope();var queue=scope.ServiceProvider.GetRequiredService<CustomerPostingQueue>();
                    var job=await queue.ClaimAsync(ct);
                    if(job is not null)
                    {
                        using var deadline=CancellationTokenSource.CreateLinkedTokenSource(ct);deadline.CancelAfter(TimeSpan.FromMinutes(3));
                        var zeus=scope.ServiceProvider.GetRequiredService<ZeusTransport>();
                        ZeusResult result;
                        var current=await scope.ServiceProvider.GetRequiredService<ZeusRepository>().SettingsAsync(job.EmpresaId,deadline.Token);
                        if(current?.Configuracion.Habilitado!=true||current.Configuracion.ServidorEsperado!=job.Snapshot.Configuracion.ServidorEsperado||current.Configuracion.BaseEsperada!=job.Snapshot.Configuracion.BaseEsperada)
                            result=new("RECHAZADO",Error:"Integración deshabilitada o destino Zeus modificado; no se envió.");
                        else
                        {
                            result=new("PENDIENTE");
                            if(job.Tipo=="FACTURA")
                            {
                                var client=(await scope.ServiceProvider.GetRequiredService<CustomerRepository>().ListAsync(job.EmpresaId,deadline.Token))
                                    .Single(x=>x.TerceroId==job.Snapshot.Origen.ProveedorId);
                                var created=await zeus.EnsureCustomerMasterAsync(job.EmpresaId,job.Snapshot.Configuracion,client,job.Snapshot.ClienteDocumento!.CuentaCliente,deadline.Token);
                                if(created.Estado!="CLIENTE")result=new(created.Estado,Error:created.Mensaje);
                                else await queue.MarkCustomerCreatedAsync(job.EmpresaId,client.TerceroId,deadline.Token);
                            }
                            if(result.Estado=="PENDIENTE")result=await zeus.SendAsync(job.EmpresaId,job.Snapshot,job.Clave,deadline.Token);
                        }
                        using var finish=new CancellationTokenSource(TimeSpan.FromSeconds(15));await queue.FinishAsync(job,result,finish.Token);
                    }
                }
            }
            catch(OperationCanceledException)when(ct.IsCancellationRequested){break;}
            catch(Exception e){logger.LogWarning("Envío de factura/recibo requiere revisión ({Type}); no se repite sin verificar.",e.GetType().Name);}
            try{await Task.Delay(TimeSpan.FromSeconds(10),ct);}catch(OperationCanceledException){break;}
        }
    }
}
