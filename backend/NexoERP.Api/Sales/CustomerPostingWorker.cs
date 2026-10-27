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
            UPDATE cxc.ReciboCaja SET ReversionEstado='INCIERTO',ReversionError=N'Envío de reversión interrumpido. Conciliar en Zeus antes de reintentar.',ReversionActualizadoEnUtc=SYSUTCDATETIME()
            WHERE ReversionEstado='ENVIANDO' AND ReversionActualizadoEnUtc<DATEADD(minute,-10,SYSUTCDATETIME());
            UPDATE ven.RefinanciacionCartera SET ZeusEstado='INCIERTO',ZeusError=N'Envío interrumpido. Conciliar en Zeus antes de reintentar.',ZeusActualizadoEnUtc=SYSUTCDATETIME()
            WHERE ZeusEstado='ENVIANDO' AND ZeusActualizadoEnUtc<DATEADD(minute,-10,SYSUTCDATETIME());
            UPDATE f SET RefinanciacionEstado='INCIERTO' FROM ven.FacturaVenta f
            JOIN ven.RefinanciacionCartera n ON n.EmpresaId=f.EmpresaId AND n.FacturaVentaId=f.FacturaVentaId
            WHERE n.ZeusEstado='INCIERTO' AND f.RefinanciacionEstado='PENDIENTE';
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
            IF NOT EXISTS(SELECT 1 FROM @Claim)
            BEGIN
                ;WITH next AS(SELECT TOP(1) * FROM cxc.ReciboCaja WITH(UPDLOCK,ROWLOCK)
                    WHERE ReversionEstado='PENDIENTE' AND ReversionSnapshot IS NOT NULL ORDER BY ReciboCajaId)
                UPDATE next SET ReversionEstado='ENVIANDO',ReversionIntentos=ReversionIntentos+1,ReversionActualizadoEnUtc=SYSUTCDATETIME()
                OUTPUT 'REVERSO',inserted.ReciboCajaId,inserted.EmpresaId,inserted.ReversionGuid,inserted.ReversionSnapshot INTO @Claim;
            END;
            IF NOT EXISTS(SELECT 1 FROM @Claim)
            BEGIN
                ;WITH next AS(SELECT TOP(1) * FROM ven.RefinanciacionCartera WITH(UPDLOCK,ROWLOCK)
                    WHERE ZeusEstado='PENDIENTE' ORDER BY RefinanciacionCarteraId)
                UPDATE next SET ZeusEstado='ENVIANDO',ZeusIntentos=ZeusIntentos+1,ZeusActualizadoEnUtc=SYSUTCDATETIME()
                OUTPUT 'NOTA',inserted.RefinanciacionCarteraId,inserted.EmpresaId,inserted.OperacionGuid,inserted.Snapshot INTO @Claim;
            END;
            SELECT Tipo,Id,EmpresaId,Clave,Snapshot FROM @Claim;
            """;
        await using var r=await q.ExecuteReaderAsync(ct);
        return await r.ReadAsync(ct)?new(r.GetString(0),r.GetInt64(1),r.GetInt64(2),r.GetGuid(3),JsonSerializer.Deserialize<ZeusSnapshot>(r.GetString(4))!):null;
    }
    public async Task FinishAsync(CustomerPostingJob job,ZeusResult result,CancellationToken ct)
    {
        if(job.Tipo=="REVERSO")
        {
            await FinishReversalAsync(job,result,ct);return;
        }
        if(job.Tipo=="NOTA")
        {
            await FinishNoteAsync(job,result,ct);return;
        }
        await using var c=await connections.OpenAsync(job.EmpresaId,false,ct);
        var table=job.Tipo=="FACTURA"?"ven.FacturaVenta":"cxc.ReciboCaja";
        var key=job.Tipo=="FACTURA"?"FacturaVentaId":"ReciboCajaId";
        await using var q=ZeusRepository.Command(c,$"UPDATE {table} SET ZeusEstado=@State,ZeusFuente=@F,ZeusDocumento=@N,ZeusError=@Error,ZeusActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E AND {key}=@Id AND ZeusEstado IN('ENVIANDO','INCIERTO')",job.EmpresaId);
        ZeusRepository.Add(q,"@Id",job.Id);ZeusRepository.Add(q,"@State",result.Estado);
        q.Parameters.AddWithValue("@F",(object?)result.Fuente??DBNull.Value);q.Parameters.AddWithValue("@N",(object?)result.Documento??DBNull.Value);
        q.Parameters.AddWithValue("@Error",(object?)result.Error??DBNull.Value);
        await q.ExecuteNonQueryAsync(ct);
    }
    private async Task FinishReversalAsync(CustomerPostingJob job,ZeusResult result,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(job.EmpresaId,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(System.Data.IsolationLevel.Serializable,ct);
        await using var q=ZeusRepository.Command(c,"SELECT Tipo,ZeusEstado,ReversionEstado,Total,ReversionPor FROM cxc.ReciboCaja WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND ReciboCajaId=@Id",job.EmpresaId,tx);
        ZeusRepository.Add(q,"@Id",job.Id);
        string type;long user;
        await using(var r=await q.ExecuteReaderAsync(ct))
        {
            if(!await r.ReadAsync(ct)||r.GetString(1)!="CONTABILIZADO"||r.GetString(2) is not("ENVIANDO" or "INCIERTO"))
                throw new InvalidOperationException("El recibo o su reversión cambiaron antes de confirmar Zeus.");
            type=r.GetString(0);user=r.GetInt64(4);
        }
        if(result.Estado=="CONTABILIZADO")
        {
            if(type=="ANTICIPO")
            {
                q.CommandText="SELECT ISNULL(SUM(Valor),0) FROM cxc.ReciboCajaConcepto WHERE EmpresaId=@E AND ReciboCajaId=@Id AND Codigo='ANTICIPO'";
                var purchaseAdvance=Convert.ToDecimal(await q.ExecuteScalarAsync(ct));
                if(purchaseAdvance>0)
                {
                    q.CommandText="UPDATE cxc.AnticipoCliente SET Saldo=0 WHERE EmpresaId=@E AND ReciboCajaId=@Id AND Saldo=@Advance";
                    ZeusRepository.Add(q,"@Advance",purchaseAdvance);
                    if(await q.ExecuteNonQueryAsync(ct)!=1)throw new InvalidOperationException("El anticipo fue utilizado mientras se procesaba la reversión; requiere conciliación.");
                    q.Parameters.RemoveAt("@Advance");
                }
            }
            if(type=="CARTERA")
            {
                q.CommandText="SELECT FacturaVentaId,FacturaVentaCuotaId,Valor FROM cxc.ReciboCajaAplicacion WHERE EmpresaId=@E AND ReciboCajaId=@Id ORDER BY ReciboCajaAplicacionId";
                var lines=new List<(long Invoice,long? Installment,decimal Value)>();
                await using(var r=await q.ExecuteReaderAsync(ct))while(await r.ReadAsync(ct))
                    lines.Add((r.GetInt64(0),r.IsDBNull(1)?null:r.GetInt64(1),r.GetDecimal(2)));
                foreach(var line in lines)
                {
                    ZeusRepository.Add(q,"@Invoice",line.Invoice);ZeusRepository.Add(q,"@Value",line.Value);
                    q.CommandText="UPDATE ven.FacturaVenta SET SaldoPendiente=SaldoPendiente+@Value WHERE EmpresaId=@E AND FacturaVentaId=@Invoice AND RefinanciacionEstado='LIBRE'";
                    if(await q.ExecuteNonQueryAsync(ct)!=1)throw new InvalidOperationException("La factura fue refinanciada mientras se procesaba la reversión; requiere conciliación.");
                    if(line.Installment.HasValue)
                    {
                        ZeusRepository.Add(q,"@Installment",line.Installment.Value);
                        q.CommandText="UPDATE ven.FacturaVentaCuota SET SaldoPendiente=SaldoPendiente+@Value WHERE EmpresaId=@E AND FacturaVentaCuotaId=@Installment AND FacturaVentaId=@Invoice AND EstadoPlan='ACTIVA'";
                        if(await q.ExecuteNonQueryAsync(ct)!=1)throw new InvalidOperationException("La cuota cambió mientras se procesaba la reversión; requiere conciliación.");
                        q.Parameters.RemoveAt("@Installment");
                    }
                    q.Parameters.RemoveAt("@Invoice");q.Parameters.RemoveAt("@Value");
                }
            }
        }
        q.CommandText="""
            UPDATE cxc.ReciboCaja SET ReversionEstado=@State,ReversionFuente=@F,ReversionDocumento=@N,
                ReversionError=@Error,ReversionActualizadoEnUtc=SYSUTCDATETIME(),
                ZeusEstado=CASE WHEN @State='CONTABILIZADO' THEN 'REVERTIDO' ELSE ZeusEstado END
            WHERE EmpresaId=@E AND ReciboCajaId=@Id AND ReversionEstado IN('ENVIANDO','INCIERTO')
            """;
        ZeusRepository.Add(q,"@State",result.Estado);ZeusRepository.Add(q,"@F",(object?)result.Fuente??DBNull.Value);
        ZeusRepository.Add(q,"@N",(object?)result.Documento??DBNull.Value);ZeusRepository.Add(q,"@Error",(object?)result.Error??DBNull.Value);
        if(await q.ExecuteNonQueryAsync(ct)!=1)throw new InvalidOperationException("La reversión cambió de estado.");
        if(result.Estado=="CONTABILIZADO")
        {
            q.CommandText="INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@E,@User,'REVERTIR_RECIBO_CAJA','cxc.ReciboCaja',CONVERT(varchar(30),@Id),@Audit,'ZEUS')";
            ZeusRepository.Add(q,"@User",user);ZeusRepository.Add(q,"@Audit",System.Text.Json.JsonSerializer.Serialize(new{fuente=result.Fuente,documento=result.Documento}));
            await q.ExecuteNonQueryAsync(ct);
        }
        await tx.CommitAsync(ct);
    }

    public async Task<string> RetryReversalAsync(long company,long id,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(System.Data.IsolationLevel.Serializable,ct);
        await using var q=ZeusRepository.Command(c,"SELECT ReversionSnapshot,SucursalId,s.Nombre FROM cxc.ReciboCaja r WITH(UPDLOCK,HOLDLOCK) JOIN core.Sucursal s ON s.EmpresaId=r.EmpresaId AND s.SucursalId=r.SucursalId WHERE r.EmpresaId=@E AND r.ReciboCajaId=@Id AND r.ReversionEstado='RECHAZADO'",company,tx);
        ZeusRepository.Add(q,"@Id",id);
        ZeusSnapshot snapshot;long branch;string branchName;
        await using(var r=await q.ExecuteReaderAsync(ct))
        {
            if(!await r.ReadAsync(ct))throw new ArgumentException("Solo se reintenta una reversión rechazada. Las inciertas se concilian.");
            snapshot=JsonSerializer.Deserialize<ZeusSnapshot>(r.GetString(0))!;branch=r.GetInt64(1);branchName=r.GetString(2);
        }
        q.CommandText="SELECT Configuracion FROM core.ZeusConfiguracion WITH(HOLDLOCK) WHERE EmpresaId=@E";
        var current=JsonSerializer.Deserialize<ZeusSettings>(await q.ExecuteScalarAsync(ct) as string??throw new ArgumentException("Configura Zeus."))!;
        if(!current.Habilitado||current.ServidorEsperado!=snapshot.Configuracion.ServidorEsperado||current.BaseEsperada!=snapshot.Configuracion.BaseEsperada)
            throw new ArgumentException("El destino Zeus cambió o está deshabilitado.");
        if(!(current.FuentesAutomaticas??[]).Any(x=>x.Movimiento=="RECIBO_CAJA"&&x.SucursalId==branch))
            throw new ArgumentException("Configura la fuente de recibos de esta sucursal.");
        var route=ZeusRouting.Resolve(current,branch,"RECIBO_CAJA",branchName);
        var renewed=snapshot with{Configuracion=snapshot.Configuracion with{Fuente=route.Fuente,Serie=route.Serie,UnidadNegocio=route.UnidadNegocio,TipoFactura=route.TipoFactura,SucursalOperacion=route.SucursalOperacion}};
        q.CommandText="UPDATE cxc.ReciboCaja SET ReversionSnapshot=@Snapshot,ReversionEstado='PENDIENTE',ReversionError=NULL,ReversionActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E AND ReciboCajaId=@Id AND ReversionEstado='RECHAZADO'";
        ZeusRepository.Add(q,"@Snapshot",JsonSerializer.Serialize(renewed));
        if(await q.ExecuteNonQueryAsync(ct)!=1)throw new ArgumentException("La reversión cambió de estado.");
        await tx.CommitAsync(ct);return route.Fuente;
    }

    public async Task<ZeusResult> ReconcileReversalAsync(long company,long id,ZeusTransport transport,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"SELECT ReversionGuid,ReversionSnapshot FROM cxc.ReciboCaja WHERE EmpresaId=@E AND ReciboCajaId=@Id AND ReversionEstado='INCIERTO'",company);
        ZeusRepository.Add(q,"@Id",id);Guid key;ZeusSnapshot snapshot;
        await using(var r=await q.ExecuteReaderAsync(ct))
        {
            if(!await r.ReadAsync(ct))throw new ArgumentException("La reversión no está en estado incierto.");
            key=r.GetGuid(0);snapshot=JsonSerializer.Deserialize<ZeusSnapshot>(r.GetString(1))!;
        }
        var result=await transport.ReconcileAsync(company,snapshot,key,ct);
        if(result.Estado=="CONTABILIZADO")await FinishReversalAsync(new("REVERSO",id,company,key,snapshot),result,ct);
        return result;
    }
    private async Task FinishNoteAsync(CustomerPostingJob job,ZeusResult result,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(job.EmpresaId,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(System.Data.IsolationLevel.Serializable,ct);
        await using var q=ZeusRepository.Command(c,"""
            SELECT FacturaVentaId,SaldoAnterior,NuevoSaldo,Incremento,PlanAnterior,PlanNuevo,ZeusEstado
            FROM ven.RefinanciacionCartera WITH(UPDLOCK,HOLDLOCK)
            WHERE EmpresaId=@E AND RefinanciacionCarteraId=@Id
            """,job.EmpresaId,tx);
        ZeusRepository.Add(q,"@Id",job.Id);
        long invoice;decimal oldBalance,newBalance,increase;PortfolioOldInstallment[] oldPlan;PortfolioInstallment[] newPlan;
        await using(var r=await q.ExecuteReaderAsync(ct))
        {
            if(!await r.ReadAsync(ct)||r.GetString(6) is not("ENVIANDO" or "INCIERTO"))throw new ArgumentException("La nota cambió de estado antes de confirmar Zeus.");
            invoice=r.GetInt64(0);oldBalance=r.GetDecimal(1);newBalance=r.GetDecimal(2);increase=r.GetDecimal(3);
            oldPlan=JsonSerializer.Deserialize<PortfolioOldInstallment[]>(r.GetString(4))!;
            newPlan=JsonSerializer.Deserialize<PortfolioInstallment[]>(r.GetString(5))!;
        }
        ZeusRepository.Add(q,"@Invoice",invoice);
        if(result.Estado=="CONTABILIZADO")
        {
            q.CommandText="SELECT SaldoPendiente,PlanVersion FROM ven.FacturaVenta WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND FacturaVentaId=@Invoice AND RefinanciacionEstado IN('PENDIENTE','INCIERTO')";
            int version;
            await using(var r=await q.ExecuteReaderAsync(ct))
            {
                if(!await r.ReadAsync(ct)||r.GetDecimal(0)!=oldBalance)throw new InvalidOperationException("El saldo ERP cambió mientras se confirmó la nota; conciliar manualmente antes de liberar cartera.");
                version=r.GetInt32(1);
            }
            foreach(var old in oldPlan)
            {
                q.CommandText="UPDATE ven.FacturaVentaCuota SET EstadoPlan='REFINANCIADA' WHERE EmpresaId=@E AND FacturaVentaId=@Invoice AND FacturaVentaCuotaId=@Installment AND PlanVersion=@Version AND EstadoPlan='ACTIVA' AND SaldoPendiente=@Balance";
                ZeusRepository.Add(q,"@Installment",old.Id);ZeusRepository.Add(q,"@Version",version);ZeusRepository.Add(q,"@Balance",old.Saldo);
                if(await q.ExecuteNonQueryAsync(ct)!=1)throw new InvalidOperationException("Una cuota anterior cambió durante la confirmación.");
                q.Parameters.RemoveAt("@Installment");q.Parameters.RemoveAt("@Version");q.Parameters.RemoveAt("@Balance");
            }
            for(var i=0;i<newPlan.Length;i++)
            {
                var due=newPlan[i];
                q.CommandText="INSERT ven.FacturaVentaCuota(EmpresaId,FacturaVentaId,PlanVersion,EstadoPlan,NumeroCuota,FechaVencimiento,ValorOriginal,SaldoPendiente,TipoCuota) VALUES(@E,@Invoice,@Version,'ACTIVA',@Number,@Due,@Value,@Value,@Type)";
                ZeusRepository.Add(q,"@Version",version+1);ZeusRepository.Add(q,"@Number",i+1);
                ZeusRepository.Add(q,"@Due",due.Vencimiento.ToDateTime(TimeOnly.MinValue));ZeusRepository.Add(q,"@Value",due.Valor);ZeusRepository.Add(q,"@Type",due.Tipo);
                await q.ExecuteNonQueryAsync(ct);
                foreach(var name in new[]{"@Version","@Number","@Due","@Value","@Type"})q.Parameters.RemoveAt(name);
            }
            q.CommandText="UPDATE ven.FacturaVenta SET SaldoPendiente=@New,RefinanciacionAdicional=RefinanciacionAdicional+@Increase,PlanVersion=PlanVersion+1,Vencimiento=@First,Cuotas=@Count,FrecuenciaCuotas='PERSONALIZADA',RefinanciacionEstado='LIBRE' WHERE EmpresaId=@E AND FacturaVentaId=@Invoice AND SaldoPendiente=@Old";
            ZeusRepository.Add(q,"@New",newBalance);ZeusRepository.Add(q,"@Increase",increase);ZeusRepository.Add(q,"@First",newPlan[0].Vencimiento.ToDateTime(TimeOnly.MinValue));ZeusRepository.Add(q,"@Count",newPlan.Length);ZeusRepository.Add(q,"@Old",oldBalance);
            if(await q.ExecuteNonQueryAsync(ct)!=1)throw new InvalidOperationException("No se pudo activar el nuevo plan tras confirmar Zeus.");
        }
        else if(result.Estado=="INCIERTO")
        {
            q.CommandText="UPDATE ven.FacturaVenta SET RefinanciacionEstado='INCIERTO' WHERE EmpresaId=@E AND FacturaVentaId=@Invoice";
            await q.ExecuteNonQueryAsync(ct);
        }
        q.CommandText="UPDATE ven.RefinanciacionCartera SET ZeusEstado=@State,ZeusFuente=@F,ZeusDocumento=@N,ZeusError=@Error,ZeusActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E AND RefinanciacionCarteraId=@Id AND ZeusEstado IN('ENVIANDO','INCIERTO')";
        ZeusRepository.Add(q,"@State",result.Estado);ZeusRepository.Add(q,"@F",(object?)result.Fuente??DBNull.Value);
        ZeusRepository.Add(q,"@N",(object?)result.Documento??DBNull.Value);ZeusRepository.Add(q,"@Error",(object?)result.Error??DBNull.Value);
        if(await q.ExecuteNonQueryAsync(ct)!=1)throw new InvalidOperationException("La nota cambió de estado antes de cerrar la confirmación.");
        await tx.CommitAsync(ct);
    }
    public async Task<string> RetryAsync(long company,string type,long id,CancellationToken ct)
    {
        var (table,key)=Table(type);
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(System.Data.IsolationLevel.Serializable,ct);
        await using var q=ZeusRepository.Command(c,$"SELECT d.Snapshot,d.SucursalId,s.Nombre FROM {table} d WITH(UPDLOCK,HOLDLOCK) JOIN core.Sucursal s ON s.EmpresaId=d.EmpresaId AND s.SucursalId=d.SucursalId WHERE d.EmpresaId=@E AND d.{key}=@Id AND d.ZeusEstado='RECHAZADO'",company,tx);
        ZeusRepository.Add(q,"@Id",id);
        ZeusSnapshot snapshot;long branch;string branchName;
        await using(var r=await q.ExecuteReaderAsync(ct))
        {
            if(!await r.ReadAsync(ct)||r.IsDBNull(0))throw new ArgumentException("Solo se reenvían rechazos confirmados. Los inciertos se concilian.");
            snapshot=JsonSerializer.Deserialize<ZeusSnapshot>(r.GetString(0))??throw new ArgumentException("El comprobante guardado no es válido.");
            branch=r.GetInt64(1);branchName=r.GetString(2);
        }
        q.CommandText="SELECT Configuracion FROM core.ZeusConfiguracion WITH(HOLDLOCK) WHERE EmpresaId=@E";
        var current=JsonSerializer.Deserialize<ZeusSettings>(await q.ExecuteScalarAsync(ct) as string??throw new ArgumentException("Configura Zeus para esta empresa."))!;
        if(!current.Habilitado||current.ServidorEsperado!=snapshot.Configuracion.ServidorEsperado||current.BaseEsperada!=snapshot.Configuracion.BaseEsperada)
            throw new ArgumentException("El destino Zeus cambió o está deshabilitado. No se puede reintentar el comprobante anterior.");
        var movement=type switch{"RECIBO"=>"RECIBO_CAJA","NOTA"=>"NOTA_CARTERA",_=>"FACTURACION"};
        if(!(current.FuentesAutomaticas??[]).Any(x=>x.Movimiento==movement&&x.SucursalId==branch))
            throw new ArgumentException($"Configura la fuente {movement} de esta sucursal antes de reintentar.");
        var route=ZeusRouting.Resolve(current,branch,movement,branchName);
        // El comprobante y sus cuentas permanecen congelados. Solo se renueva la ruta
        // del rechazo confirmado; nunca se cambia el destino ni se reenvía un incierto.
        var previous=snapshot.Configuracion.Fuente;
        var rebased=snapshot with{Configuracion=snapshot.Configuracion with
        {
            Fuente=route.Fuente,Serie=route.Serie,UnidadNegocio=route.UnidadNegocio,
            TipoFactura=route.TipoFactura,SucursalOperacion=route.SucursalOperacion
        }};
        q.CommandText=$"UPDATE {table} SET Snapshot=@Snapshot,ZeusEstado='PENDIENTE',ZeusError=NULL,ZeusActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E AND {key}=@Id AND ZeusEstado='RECHAZADO'";
        ZeusRepository.Add(q,"@Snapshot",JsonSerializer.Serialize(rebased));
        if(await q.ExecuteNonQueryAsync(ct)!=1)throw new ArgumentException("El estado cambió. Actualiza antes de reintentar.");
        q.CommandText="INSERT audit.Evento(EmpresaId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@E,'ZEUS_REINTENTAR',@Table,CONVERT(varchar(30),@Id),@Audit,'ZEUS')";
        ZeusRepository.Add(q,"@Table",table);
        ZeusRepository.Add(q,"@Audit",JsonSerializer.Serialize(new{fuenteAnterior=previous,fuenteNueva=route.Fuente,movimiento=movement}));
        await q.ExecuteNonQueryAsync(ct);
        await tx.CommitAsync(ct);
        return route.Fuente;
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
        "NOTA"=>("ven.RefinanciacionCartera","RefinanciacionCarteraId"),
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
            catch(Exception e){logger.LogWarning("Envío de factura/recibo/nota requiere revisión ({Type}); no se repite sin verificar.",e.GetType().Name);}
            try{await Task.Delay(TimeSpan.FromSeconds(10),ct);}catch(OperationCanceledException){break;}
        }
    }
}
