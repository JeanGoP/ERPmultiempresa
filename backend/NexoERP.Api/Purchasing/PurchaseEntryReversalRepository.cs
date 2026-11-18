using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;
using NexoERP.Api.Zeus;

namespace NexoERP.Api.Purchasing;

public sealed record PurchaseEntryReversalInput(long PeriodoInventarioId,DateOnly FechaContable,string Motivo);
public sealed record PurchaseEntryReversalZeusStatus(string Estado,string Mensaje,string? Fuente=null,string? Documento=null);
public sealed record PurchaseEntryReversalStatus(long DocumentoProveedorId,long? RecepcionMercanciaId,long? ReversionId,
    string Estado,DateOnly? FechaContable,string? Motivo,PurchaseEntryReversalZeusStatus Zeus,string EstadoDocumento,
    string? EstadoEntrada,string? EstadoOriginalZeus);
public sealed record PurchaseEntryReversalResponse(long ReversionId,long RecepcionMercanciaId,long DocumentoProveedorId,
    string Estado,int Movimientos,bool YaExistia,PurchaseEntryReversalZeusStatus Zeus);
internal sealed record PurchaseEntryReversalJob(long Company,long Document,long Reversal,Guid Key,ZeusSnapshot Snapshot);

public sealed class PurchaseEntryReversalRepository(TenantConnectionFactory connections,ZeusTransport transport)
{
    public async Task<PurchaseEntryReversalStatus?> StatusAsync(long company,long document,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(company,false,ct);
        return await ReadStatusAsync(connection,null,company,document,ct);
    }

    public async Task<PurchaseEntryReversalResponse> RequestAsync(long company,long document,PurchaseEntryReversalInput input,long user,CancellationToken ct)
    {
        var reason=input.Motivo?.Trim();
        if(input.PeriodoInventarioId<=0||input.FechaContable==default||reason?.Length is not (>=10 and <=500))
            throw new ArgumentException("Escoge la fecha, el período de inventario y escribe un motivo de 10 a 500 caracteres.");
        await using var connection=await connections.OpenAsync(company,false,ct);
        await using var transaction=(SqlTransaction)await connection.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        await using var command=ZeusRepository.Command(connection,"""
            SELECT r.RecepcionMercanciaId
            FROM comp.DocumentoProveedor d WITH(UPDLOCK,HOLDLOCK)
            LEFT JOIN inv.RecepcionMercancia r WITH(UPDLOCK,HOLDLOCK)
                ON r.EmpresaId=d.EmpresaId AND r.DocumentoProveedorId=d.DocumentoProveedorId
            WHERE d.EmpresaId=@E AND d.DocumentoProveedorId=@Document;
            """,company,transaction);
        ZeusRepository.Add(command,"@Document",document);
        var receiptValue=await command.ExecuteScalarAsync(ct);
        if(receiptValue is null or DBNull)throw new ArgumentException("El documento no tiene una entrada de mercancía en esta empresa.");
        var receipt=Convert.ToInt64(receiptValue);
        ZeusRepository.Add(command,"@Receipt",receipt);
        command.CommandText="SELECT ReversionEntradaMercanciaId FROM inv.ReversionEntradaMercancia WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND RecepcionMercanciaId=@Receipt";
        var existing=await command.ExecuteScalarAsync(ct);
        string? originalJson=null;
        ZeusSnapshot? reversal=null;
        if(existing is null)
        {
            command.CommandText="""
                SELECT Estado,Clave,Snapshot,Fuente,Documento
                FROM core.ZeusEnvio WITH(UPDLOCK,HOLDLOCK)
                WHERE EmpresaId=@E AND RecepcionMercanciaId=@Receipt;
                """;
            string? state=null,source=null,number=null;
            Guid originalKey=Guid.Empty;
            await using(var reader=await command.ExecuteReaderAsync(ct))
            {
                if(await reader.ReadAsync(ct))
                {
                    state=reader.GetString(0);originalKey=reader.GetGuid(1);
                    originalJson=reader.IsDBNull(2)?null:reader.GetString(2);
                    source=reader.IsDBNull(3)?null:reader.GetString(3);
                    number=reader.IsDBNull(4)?null:reader.GetString(4);
                }
            }
            if(state is "ENVIANDO" or "INCIERTO")
                throw new ArgumentException("La entrada tiene un envío en curso o incierto en Zeus. Concilia el comprobante original antes de revertir.");
            if(state=="CONTABILIZADO")
            {
                ZeusSnapshot? original;
                try{original=originalJson is null?null:JsonSerializer.Deserialize<ZeusSnapshot>(originalJson);}
                catch(JsonException){throw new ArgumentException("El comprobante original de Zeus no conserva datos válidos para su reversión.");}
                if(original is null||original.Origen.RecepcionId!=receipt||source is null||number is null)
                    throw new ArgumentException("La entrada no conserva el comprobante original confirmado de Zeus.");
                reversal=ZeusPurchaseEntryReversalPolicy.Build(original,originalKey,source,number,input.FechaContable,reason!);
                try{await transport.CheckPurchaseEntryReversalAsync(company,reversal,ct);}
                catch(SqlException){throw new ArgumentException("No se pudo comprobar el comprobante y el saldo exacto de la factura en Zeus. La entrada no fue revertida.");}
                catch(InvalidOperationException error){throw new ArgumentException("El comprobante original de Zeus requiere revisión. "+error.Message);}
            }
            else if(state is null or "PENDIENTE" or "REQUIERE_REVISION" or "RECHAZADO" or "CANCELADO")
            {
                command.CommandText="""
                    UPDATE core.ZeusEnvio
                    SET Estado='CANCELADO',Error=N'Envío cancelado al revertir completamente la entrada en Nexo.',
                        ActualizadoEnUtc=SYSUTCDATETIME()
                    WHERE EmpresaId=@E AND RecepcionMercanciaId=@Receipt
                        AND Estado IN('PENDIENTE','REQUIERE_REVISION','RECHAZADO');
                    """;
                await command.ExecuteNonQueryAsync(ct);
            }
            else throw new ArgumentException("Revisa el estado del comprobante original en Zeus antes de revertir la entrada.");
        }

        var operation=await ReverseLocalAsync(connection,transaction,company,receipt,input,user,reason!,ct);
        if(!operation.YaExistia)
        {
            command.CommandText="""
                UPDATE inv.ReversionEntradaMercancia
                SET ZeusEstado=@State,ZeusSnapshotOriginal=@Original,ZeusSnapshot=@Snapshot,
                    ZeusActualizadoEnUtc=SYSUTCDATETIME()
                WHERE EmpresaId=@E AND ReversionEntradaMercanciaId=@Reversal;
                """;
            ZeusRepository.Add(command,"@State",reversal is null?"SIN_ENVIO":"PENDIENTE");
            ZeusRepository.Add(command,"@Original",(object?)originalJson??DBNull.Value);
            ZeusRepository.Add(command,"@Snapshot",reversal is null?DBNull.Value:JsonSerializer.Serialize(reversal));
            ZeusRepository.Add(command,"@Reversal",operation.ReversionId);
            await command.ExecuteNonQueryAsync(ct);
        }
        var status=await ReadStatusAsync(connection,transaction,company,document,ct)
            ??throw new InvalidOperationException("La reversión no quedó registrada.");
        await transaction.CommitAsync(ct);
        return operation with {Zeus=status.Zeus};
    }

    private static async Task<PurchaseEntryReversalResponse> ReverseLocalAsync(SqlConnection connection,SqlTransaction transaction,
        long company,long receipt,PurchaseEntryReversalInput input,long user,string reason,CancellationToken ct)
    {
        await using var command=connection.CreateCommand();command.Transaction=transaction;command.CommandTimeout=120;
        command.CommandType=CommandType.StoredProcedure;command.CommandText="inv.usp_RevertirEntradaMercancia";
        command.Parameters.AddWithValue("@EmpresaId",company);
        command.Parameters.AddWithValue("@RecepcionMercanciaId",receipt);
        command.Parameters.AddWithValue("@PeriodoInventarioId",input.PeriodoInventarioId);
        command.Parameters.Add("@FechaContable",SqlDbType.Date).Value=input.FechaContable.ToDateTime(TimeOnly.MinValue);
        command.Parameters.Add("@Motivo",SqlDbType.NVarChar,500).Value=reason;
        command.Parameters.AddWithValue("@UsuarioId",user);
        command.Parameters.AddWithValue("@CorrelationId",Guid.NewGuid());
        PurchaseEntryReversalResponse? response=null;
        await using var reader=await command.ExecuteReaderAsync(ct);
        do
        {
            var final=Enumerable.Range(0,reader.FieldCount).Any(index=>reader.GetName(index)=="ReversionEntradaMercanciaId");
            while(await reader.ReadAsync(ct))
            {
                if(final)response=new(Convert.ToInt64(reader["ReversionEntradaMercanciaId"]),Convert.ToInt64(reader["RecepcionMercanciaId"]),
                    Convert.ToInt64(reader["DocumentoProveedorId"]),Convert.ToString(reader["Estado"])!,Convert.ToInt32(reader["Movimientos"]),
                    Convert.ToBoolean(reader["YaExistia"]),new("SIN_ENVIO","Reversión registrada en Nexo."));
            }
        }while(await reader.NextResultAsync(ct));
        return response??throw new InvalidOperationException("La reversión de la entrada no confirmó su resultado.");
    }

    private static async Task<PurchaseEntryReversalStatus?> ReadStatusAsync(SqlConnection connection,SqlTransaction? transaction,
        long company,long document,CancellationToken ct)
    {
        await using var command=ZeusRepository.Command(connection,"""
            SELECT d.DocumentoProveedorId,r.RecepcionMercanciaId,v.ReversionEntradaMercanciaId,v.Estado,v.FechaContable,v.Motivo,
                   v.ZeusEstado,v.ZeusError,v.ZeusFuente,v.ZeusDocumento,d.Estado,r.Estado,j.Estado
            FROM comp.DocumentoProveedor d
            LEFT JOIN inv.RecepcionMercancia r ON r.EmpresaId=d.EmpresaId AND r.DocumentoProveedorId=d.DocumentoProveedorId
            LEFT JOIN inv.ReversionEntradaMercancia v ON v.EmpresaId=r.EmpresaId AND v.RecepcionMercanciaId=r.RecepcionMercanciaId
            LEFT JOIN core.ZeusEnvio j ON j.EmpresaId=r.EmpresaId AND j.RecepcionMercanciaId=r.RecepcionMercanciaId
            WHERE d.EmpresaId=@E AND d.DocumentoProveedorId=@Document;
            """,company,transaction);
        ZeusRepository.Add(command,"@Document",document);
        await using var reader=await command.ExecuteReaderAsync(ct);
        if(!await reader.ReadAsync(ct))return null;
        string? Optional(int at)=>reader.IsDBNull(at)?null:reader.GetString(at);
        var state=Optional(6)??"SIN_REVERSIÓN";
        var source=Optional(8);var number=Optional(9);
        var message=state switch{
            "SIN_ENVIO"=>"Entrada revertida en Nexo. El envío original no estaba confirmado en Zeus y fue cancelado; no se generó contrasiento.",
            "PENDIENTE"=>"Entrada revertida en Nexo. Contrasiento pendiente de contabilizar en Zeus.",
            "ENVIANDO"=>"Entrada revertida en Nexo. Enviando el contrasiento a Zeus.",
            "CONTABILIZADO"=>$"Entrada revertida en Nexo y en Zeus. Comprobante {source} {number}.",
            "SIN_REVERSIÓN"=>"La entrada aún no tiene una reversión registrada.",
            _=>Optional(7)??$"Reversión en Nexo registrada. Zeus: {state}."
        };
        return new(reader.GetInt64(0),reader.IsDBNull(1)?null:reader.GetInt64(1),reader.IsDBNull(2)?null:reader.GetInt64(2),
            Optional(3)??"SIN_REVERSIÓN",reader.IsDBNull(4)?null:DateOnly.FromDateTime(reader.GetDateTime(4)),Optional(5),
            new(state,message,source,number),reader.GetString(10),Optional(11),Optional(12));
    }

    public async Task<PurchaseEntryReversalStatus> RetryAsync(long company,long document,long user,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(company,false,ct);
        await using var command=ZeusRepository.Command(connection,"""
            SET XACT_ABORT ON; BEGIN TRANSACTION;
            UPDATE inv.ReversionEntradaMercancia SET ZeusEstado='PENDIENTE',ZeusError=NULL,ZeusActualizadoEnUtc=SYSUTCDATETIME()
            WHERE EmpresaId=@E AND DocumentoProveedorId=@Document AND ZeusEstado='RECHAZADO' AND ZeusSnapshot IS NOT NULL;
            IF @@ROWCOUNT<>1 THROW 51993,'Solo puede reintentarse una reversión rechazada con comprobante congelado.',1;
            INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,AplicacionOrigen)
            VALUES(@E,@User,'REINTENTAR_REVERSIÓN_ENTRADA','comp.DocumentoProveedor',CONVERT(nvarchar(100),@Document),'ZEUS');
            COMMIT;
            """,company);
        ZeusRepository.Add(command,"@Document",document);ZeusRepository.Add(command,"@User",user);
        await command.ExecuteNonQueryAsync(ct);
        return (await StatusAsync(company,document,ct))!;
    }

    public async Task<PurchaseEntryReversalStatus> ReconcileAsync(long company,long document,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(company,false,ct);
        await using var command=ZeusRepository.Command(connection,"""
            SELECT ReversionEntradaMercanciaId,OperacionGuid,ZeusSnapshot
            FROM inv.ReversionEntradaMercancia WHERE EmpresaId=@E AND DocumentoProveedorId=@Document AND ZeusEstado='INCIERTO';
            """,company);
        ZeusRepository.Add(command,"@Document",document);
        PurchaseEntryReversalJob job;
        await using(var reader=await command.ExecuteReaderAsync(ct))
        {
            if(!await reader.ReadAsync(ct)||reader.IsDBNull(2))throw new ArgumentException("La entrada no tiene una reversión incierta para conciliar.");
            job=new(company,document,reader.GetInt64(0),reader.GetGuid(1),JsonSerializer.Deserialize<ZeusSnapshot>(reader.GetString(2))!);
        }
        var result=await transport.ReconcileAsync(company,job.Snapshot,job.Key,ct);
        await FinishAsync(job,result,ct);
        return (await StatusAsync(company,document,ct))!;
    }

    internal async Task<PurchaseEntryReversalJob?> ClaimAsync(CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(null,true,ct);
        await using var command=connection.CreateCommand();
        command.CommandText="""
            UPDATE inv.ReversionEntradaMercancia SET ZeusEstado='INCIERTO',
                ZeusError=N'Envío interrumpido. Concilia la reversión en Zeus antes de reenviar.',ZeusActualizadoEnUtc=SYSUTCDATETIME()
            WHERE ZeusEstado='ENVIANDO' AND ZeusActualizadoEnUtc<DATEADD(minute,-15,SYSUTCDATETIME());
            ;WITH job AS(
                SELECT TOP(1) * FROM inv.ReversionEntradaMercancia WITH(UPDLOCK,READPAST,READCOMMITTEDLOCK)
                WHERE ZeusEstado='PENDIENTE' AND ZeusSnapshot IS NOT NULL ORDER BY ReversionEntradaMercanciaId
            )
            UPDATE job SET ZeusEstado='ENVIANDO',ZeusIntentos=ZeusIntentos+1,ZeusActualizadoEnUtc=SYSUTCDATETIME()
            OUTPUT inserted.EmpresaId,inserted.DocumentoProveedorId,inserted.ReversionEntradaMercanciaId,inserted.OperacionGuid,inserted.ZeusSnapshot;
            """;
        await using var reader=await command.ExecuteReaderAsync(ct);
        return await reader.ReadAsync(ct)?new(reader.GetInt64(0),reader.GetInt64(1),reader.GetInt64(2),reader.GetGuid(3),
            JsonSerializer.Deserialize<ZeusSnapshot>(reader.GetString(4))!):null;
    }

    internal async Task FinishAsync(PurchaseEntryReversalJob job,ZeusResult result,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(job.Company,false,ct);
        await using var command=ZeusRepository.Command(connection,"""
            SET XACT_ABORT ON; BEGIN TRANSACTION;
            UPDATE inv.ReversionEntradaMercancia SET ZeusEstado=@State,ZeusFuente=@Source,ZeusDocumento=@Number,
                ZeusError=@Error,ZeusActualizadoEnUtc=SYSUTCDATETIME()
            WHERE EmpresaId=@E AND ReversionEntradaMercanciaId=@Id AND OperacionGuid=@Key AND ZeusEstado IN('ENVIANDO','INCIERTO');
            IF @@ROWCOUNT=1
              INSERT audit.Evento(EmpresaId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
              VALUES(@E,'ZEUS_REVERSIÓN_ENTRADA','inv.ReversionEntradaMercancia',CONVERT(nvarchar(100),@Id),
                (SELECT @State estado,@Source fuente,@Number documento,@Error error FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),'ZEUS');
            COMMIT;
            """,job.Company);
        ZeusRepository.Add(command,"@Id",job.Reversal);ZeusRepository.Add(command,"@Key",job.Key);
        ZeusRepository.Add(command,"@State",result.Estado);ZeusRepository.Add(command,"@Source",(object?)result.Fuente??DBNull.Value);
        ZeusRepository.Add(command,"@Number",(object?)result.Documento??DBNull.Value);
        var error=result.Error;ZeusRepository.Add(command,"@Error",error is null?DBNull.Value:error[..Math.Min(error.Length,2000)]);
        await command.ExecuteNonQueryAsync(ct);
    }
}
