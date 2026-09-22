using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;

namespace NexoERP.Api.Zeus;

public sealed record ZeusPostingStatus(string Estado,string Mensaje);

public sealed partial class ZeusRepository
{
    // Se ejecuta en la MISMA transacción ERP que contabiliza la entrada.
    internal static async Task<ZeusPostingStatus> EnqueueAutomaticAsync(SqlConnection c,SqlTransaction tx,long company,long receipt,long user,CancellationToken ct)
    {
        await using var q=Command(c,"SELECT Estado FROM inv.RecepcionMercancia WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND RecepcionMercanciaId=@R",company,tx);Add(q,"@R",receipt);
        if(await q.ExecuteScalarAsync(ct) as string!="CONTABILIZADA")throw new ArgumentException("La entrada debe estar contabilizada en esta empresa.");
        q.CommandText="SELECT Estado FROM core.ZeusEnvio WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND RecepcionMercanciaId=@R";
        var state=await q.ExecuteScalarAsync(ct) as string;
        if(state is "PENDIENTE" or "ENVIANDO" or "CONTABILIZADO" or "INCIERTO")return new(state,"ERP contabilizado. Zeus: "+state+". Consulta Seguimiento; no repitas la entrada.");
        q.CommandText="SELECT Configuracion FROM core.ZeusConfiguracion WITH(HOLDLOCK) WHERE EmpresaId=@E";
        var configuration=await q.ExecuteScalarAsync(ct) as string;
        if(configuration is null)return new("NO_CONFIGURADO","ERP contabilizado. Zeus no tiene configuración para esta empresa; no se envió el comprobante.");
        Add(q,"@U",user);
        q.CommandText="IF NOT EXISTS(SELECT 1 FROM core.ZeusEnvio WHERE EmpresaId=@E AND RecepcionMercanciaId=@R) INSERT core.ZeusEnvio(EmpresaId,RecepcionMercanciaId) VALUES(@E,@R);";await q.ExecuteNonQueryAsync(ct);
        ZeusSnapshot snapshot;
        try
        {
            if(!JsonSerializer.Deserialize<ZeusSettings>(configuration)!.Habilitado)throw new ArgumentException("El envío contable a Zeus está deshabilitado para esta empresa.");
            q.CommandText="""
                SELECT d.XmlOriginal,COALESCE((SELECT SUM(l.Retencion) FROM comp.DocumentoProveedorLinea l WHERE l.EmpresaId=d.EmpresaId AND l.DocumentoProveedorId=d.DocumentoProveedorId),0)
                FROM inv.RecepcionMercancia r JOIN comp.DocumentoProveedor d ON d.EmpresaId=r.EmpresaId AND d.DocumentoProveedorId=r.DocumentoProveedorId WHERE r.EmpresaId=@E AND r.RecepcionMercanciaId=@R;
                SELECT CONVERT(varchar(20),l.NumeroLinea),CASE WHEN EXISTS(SELECT 1 FROM core.ZeusBodegaCuenta WHERE EmpresaId=@E) THEN COALESCE(rl.BodegaId,r.BodegaId) END
                FROM inv.RecepcionMercancia r JOIN inv.RecepcionMercanciaLinea rl ON rl.EmpresaId=r.EmpresaId AND rl.RecepcionMercanciaId=r.RecepcionMercanciaId JOIN comp.DocumentoProveedorLinea l ON l.EmpresaId=rl.EmpresaId AND l.DocumentoProveedorLineaId=rl.DocumentoProveedorLineaId WHERE r.EmpresaId=@E AND r.RecepcionMercanciaId=@R;
                """;
            string? xml;decimal retention;var warehouses=new Dictionary<string,long?>();
            await using(var reader=await q.ExecuteReaderAsync(ct))
            {
                if(!await reader.ReadAsync(ct))throw new ArgumentException("No se encuentra la factura de la entrada.");
                xml=reader.IsDBNull(0)?null:reader.GetString(0);retention=reader.GetDecimal(1);
                await reader.NextResultAsync(ct);while(await reader.ReadAsync(ct))warehouses.Add(reader.GetString(0),reader.IsDBNull(1)?null:reader.GetInt64(1));
            }
            snapshot=await BuildAsync(c,tx,company,receipt,ZeusXmlTaxes.Parse(xml,warehouses,retention),ct);
        }
        catch(ArgumentException e)
        {
            q.CommandText="UPDATE core.ZeusEnvio SET Estado='REQUIERE_REVISION',Error=@Error,ActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E AND RecepcionMercanciaId=@R";Add(q,"@Error",e.Message);await q.ExecuteNonQueryAsync(ct);
            return new("REQUIERE_REVISION","ERP contabilizado; Zeus pendiente de corregir: "+e.Message);
        }
        q.CommandText="""
            UPDATE core.ZeusEnvio SET Estado='PENDIENTE',Snapshot=@J,AprobadoPor=@U,Error=NULL,ActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E AND RecepcionMercanciaId=@R;
            INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
            VALUES(@E,@U,'ZEUS_ENCOLAR_ENTRADA','inv.RecepcionMercancia',CONVERT(nvarchar(100),@R),@J,'ZEUS');
            """;
        Add(q,"@J",SerializeSnapshot(snapshot));await q.ExecuteNonQueryAsync(ct);
        return new("PENDIENTE","ERP contabilizado. Envío a Zeus registrado automáticamente; consulta su resultado en Seguimiento.");
    }
    public async Task<ZeusPostingStatus> RetryAutomaticAsync(long company,long receipt,long user,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        var result=await EnqueueAutomaticAsync(c,tx,company,receipt,user,ct);await tx.CommitAsync(ct);return result;
    }
    public async Task<ZeusPostingStatus> ReceiptStatusAsync(long company,long receipt,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=Command(c,"SELECT Estado,Error,Fuente,Documento FROM core.ZeusEnvio WHERE EmpresaId=@E AND RecepcionMercanciaId=@R",company);Add(q,"@R",receipt);
        await using var r=await q.ExecuteReaderAsync(ct);
        if(!await r.ReadAsync(ct))return new("SIN_ENVIO","No hay envío a Zeus registrado para esta entrada.");
        return new(r.GetString(0),r.IsDBNull(1)?$"Zeus: {r.GetString(0)}. Comprobante: {(r.IsDBNull(2)?"":r.GetString(2))} {(r.IsDBNull(3)?"":r.GetString(3))}":r.GetString(1));
    }
    internal async Task<bool> SupplierStillSendingAsync(long company,long supplier,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=Command(c,"SELECT COUNT(*) FROM core.ZeusProveedorEnvio WHERE EmpresaId=@E AND TerceroId=@P AND Estado IN('EN_COLA','ENVIANDO')",company);Add(q,"@P",supplier);
        return Convert.ToInt32(await q.ExecuteScalarAsync(ct))>0;
    }
}
