using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;
using NexoERP.Api.MasterData;

namespace NexoERP.Api.Zeus;

public sealed record ZeusSupplierJob(long EmpresaId,long TerceroId,Guid Intento,string? Servidor,string? BaseDatos);
public sealed class ZeusSupplierSync(TenantConnectionFactory connections,ZeusRepository settings,MasterDataRepository masters,ZeusTransport transport)
{
    // Debe ejecutarse en la misma transacción que guarda el proveedor del XML.
    internal static async Task EnqueueAsync(SqlConnection c,SqlTransaction tx,long company,long supplier,long user,CancellationToken ct)
    {
        await using var q=ZeusRepository.Command(c,"""
            IF NOT EXISTS(SELECT 1 FROM core.ZeusProveedorEnvio WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND TerceroId=@T)
            BEGIN
                INSERT core.ZeusProveedorEnvio(EmpresaId,TerceroId,SolicitadoPor,Servidor,BaseDatos,Mensaje)
                SELECT @E,@T,@U,JSON_VALUE(c.Configuracion,'$.ServidorEsperado'),JSON_VALUE(c.Configuracion,'$.BaseEsperada'),N'Proveedor guardado en ERP. En cola para verificar o crear en Zeus.'
                FROM (SELECT 1 n) seed LEFT JOIN core.ZeusConfiguracion c ON c.EmpresaId=@E;
                INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,AplicacionOrigen)
                VALUES(@E,@U,'ZEUS_PROVEEDOR_ENCOLAR','ter.Tercero',CONVERT(nvarchar(100),@T),'XML');
            END;
            """,company,tx);
        ZeusRepository.Add(q,"@T",supplier);ZeusRepository.Add(q,"@U",user);await q.ExecuteNonQueryAsync(ct);
    }
    public async Task<ZeusSupplierJob?> ClaimAsync(CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(null,true,ct);
        await using var q=c.CreateCommand();q.CommandText="""
            SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
            UPDATE core.ZeusProveedorEnvio SET Estado='INCIERTO',Mensaje=N'El envío se interrumpió. Consulta el proveedor en Zeus antes de reintentar.',ActualizadoEnUtc=SYSUTCDATETIME()
            WHERE Estado='ENVIANDO' AND ActualizadoEnUtc<DATEADD(minute,-10,SYSUTCDATETIME());
            ;WITH siguiente AS(SELECT TOP(1) * FROM core.ZeusProveedorEnvio WITH(UPDLOCK,READPAST,READCOMMITTEDLOCK) WHERE Estado='EN_COLA' ORDER BY ActualizadoEnUtc)
            UPDATE siguiente SET Estado='ENVIANDO',Intentos=Intentos+1,Intento=NEWID(),ActualizadoEnUtc=SYSUTCDATETIME(),Mensaje=N'Verificando y creando proveedor en Zeus.'
            OUTPUT inserted.EmpresaId,inserted.TerceroId,inserted.Intento,inserted.Servidor,inserted.BaseDatos;
            """;
        await using var r=await q.ExecuteReaderAsync(ct);
        return await r.ReadAsync(ct)?new(r.GetInt64(0),r.GetInt64(1),r.GetGuid(2),r.IsDBNull(3)?null:r.GetString(3),r.IsDBNull(4)?null:r.GetString(4)):null;
    }
    public async Task<ZeusSupplierJob> StartManualAsync(long company,long supplier,long user,ZeusSettings destination,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        await EnqueueAsync(c,tx,company,supplier,user,ct);
        var attempt=Guid.NewGuid();
        await using var q=ZeusRepository.Command(c,"""
            IF EXISTS(SELECT 1 FROM core.ZeusProveedorEnvio WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND TerceroId=@T AND Estado='ENVIANDO')
                THROW 51761,'El proveedor tiene un envio en curso. Actualiza antes de intentar nuevamente.',1;
            UPDATE core.ZeusProveedorEnvio SET Estado='ENVIANDO',Intento=@I,Intentos=Intentos+1,SolicitadoPor=@U,Servidor=@S,BaseDatos=@B,Mensaje=N'Envío manual solicitado.',ActualizadoEnUtc=SYSUTCDATETIME()
            WHERE EmpresaId=@E AND TerceroId=@T;
            """,company,tx);
        ZeusRepository.Add(q,"@T",supplier);ZeusRepository.Add(q,"@I",attempt);ZeusRepository.Add(q,"@U",user);
        ZeusRepository.Add(q,"@S",destination.ServidorEsperado);ZeusRepository.Add(q,"@B",destination.BaseEsperada);
        await q.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);
        return new(company,supplier,attempt,destination.ServidorEsperado,destination.BaseEsperada);
    }
    public async Task FinishAsync(ZeusSupplierJob job,ZeusSupplierSendResult result,CancellationToken ct)
    {
        var state=result.Estado=="RECHAZADO"?"PENDIENTE":result.Estado;
        await using var c=await connections.OpenAsync(job.EmpresaId,false,ct);
        await using var q=ZeusRepository.Command(c,"""
            SET XACT_ABORT ON; BEGIN TRANSACTION;
            UPDATE core.ZeusProveedorEnvio SET Estado=@S,Mensaje=@M,ActualizadoEnUtc=SYSUTCDATETIME()
            WHERE EmpresaId=@E AND TerceroId=@T AND Intento=@I AND Estado='ENVIANDO';
            IF @@ROWCOUNT=1 INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
            SELECT @E,SolicitadoPor,'ZEUS_PROVEEDOR_RESULTADO','ter.Tercero',CONVERT(nvarchar(100),@T),@J,'ZEUS'
            FROM core.ZeusProveedorEnvio WHERE EmpresaId=@E AND TerceroId=@T;
            COMMIT;
            """,job.EmpresaId);
        ZeusRepository.Add(q,"@T",job.TerceroId);ZeusRepository.Add(q,"@I",job.Intento);ZeusRepository.Add(q,"@S",state);
        ZeusRepository.Add(q,"@M",result.Mensaje.Length>1500?result.Mensaje[..1500]:result.Mensaje);ZeusRepository.Add(q,"@J",JsonSerializer.Serialize(result));
        await q.ExecuteNonQueryAsync(ct);
    }
    public async Task<ZeusSupplierSendResult> ProcessAsync(ZeusSupplierJob job,CancellationToken ct)
    {
        try
        {
            var config=await settings.SettingsAsync(job.EmpresaId,ct);
            if(config is null)return new("PENDIENTE","","Configura la conexión y cuenta general de Zeus de esta empresa; luego usa Enviar a Zeus.");
            if(!string.Equals(config.Configuracion.ServidorEsperado,job.Servidor,StringComparison.OrdinalIgnoreCase)||!string.Equals(config.Configuracion.BaseEsperada,job.BaseDatos,StringComparison.OrdinalIgnoreCase))
                return new("PENDIENTE","","El destino de Zeus cambió o no estaba configurado al importar. Revisa y usa Enviar a Zeus.");
            var supplier=(await masters.GetSuppliersAsync(job.EmpresaId,ct)).SingleOrDefault(s=>s.TerceroId==job.TerceroId);
            if(supplier is null||!supplier.Activo)return new("PENDIENTE","","El proveedor no existe o está inactivo en el ERP.");
            return await transport.SendSupplierAsync(job.EmpresaId,config.Configuracion,supplier,new(),ct);
        }
        catch(ArgumentException e){return new("PENDIENTE","",e.Message);}
        catch(SqlException e){return new("PENDIENTE","",$"No se pudo consultar o conectar con los maestros. SQL {e.Number}. Revisa la configuración y usa Enviar a Zeus.");}
        catch(OperationCanceledException){return new("INCIERTO","","La operación se interrumpió. Consulta el proveedor antes de repetir.");}
    }
}

public sealed class ZeusSupplierWorker(IServiceScopeFactory scopes,ILogger<ZeusSupplierWorker> logger):BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while(!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope=scopes.CreateScope();var sync=scope.ServiceProvider.GetRequiredService<ZeusSupplierSync>();
                var job=await sync.ClaimAsync(stoppingToken);
                if(job is not null)
                {
                    using var deadline=CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);deadline.CancelAfter(TimeSpan.FromMinutes(3));
                    var result=await sync.ProcessAsync(job,deadline.Token);
                    using var finish=new CancellationTokenSource(TimeSpan.FromSeconds(15));
                    await sync.FinishAsync(job,result,finish.Token);
                }
            }
            catch(OperationCanceledException) when(stoppingToken.IsCancellationRequested){break;}
            catch(Exception e){logger.LogWarning("No se completó el ciclo de proveedores Zeus ({Tipo}); se conserva la cola para revisión.",e.GetType().Name);}
            try{await Task.Delay(TimeSpan.FromSeconds(5),stoppingToken);}catch(OperationCanceledException){break;}
        }
    }
}
