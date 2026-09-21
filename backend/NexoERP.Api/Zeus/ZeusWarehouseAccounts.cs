using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;

namespace NexoERP.Api.Zeus;

public sealed record ZeusChartAccount(string Codigo,string Nombre);
public sealed record ZeusWarehouseAccounts(string Inventario,string IvaCompras,string IvaVentas,
    string IvaDevolucionVentas,string Ingreso,string CostoVenta,string DevolucionVenta)
{
    public string[] Codes()=>[Inventario,IvaCompras,IvaVentas,IvaDevolucionVentas,Ingreso,CostoVenta,DevolucionVenta];
    public void Validate(IEnumerable<ZeusChartAccount> chart)
    {
        var allowed=chart.Select(a=>a.Codigo).ToHashSet(StringComparer.OrdinalIgnoreCase);
        if(Codes().Any(c=>string.IsNullOrWhiteSpace(c)||c.Length>16||c!=c.Trim()||!allowed.Contains(c)))
            throw new ArgumentException("Selecciona las siete cuentas de detalle habilitadas del plan de Zeus de esta empresa.");
    }
}
public sealed record ZeusWarehouseSave(int Version,int VersionEmpresa,ZeusWarehouseAccounts Cuentas);
public sealed record ZeusWarehouseConfig(int Version,string Servidor,string BaseDatos,ZeusWarehouseAccounts? Cuentas);

public sealed partial class ZeusTransport
{
    public async Task<ZeusChartAccount[]> ChartAsync(long company,ZeusSettings settings,CancellationToken ct,bool suppliers=false)
    {
        await using var c=await OpenAsync(company,settings,ct);
        await using var q=c.CreateCommand();q.CommandType=CommandType.StoredProcedure;
        q.CommandText="dbo.SpMae_Maecont";q.CommandTimeout=30;
        q.Parameters.Add("@Op",SqlDbType.VarChar,1).Value="A"; // Solo consulta. Nunca I/U/D.
        var status=q.Parameters.Add("@Return",SqlDbType.Int);status.Direction=ParameterDirection.ReturnValue;
        var accounts=new List<ZeusChartAccount>();bool found=false;
        await using(var r=await q.ExecuteReaderAsync(ct))
        {
            do
            {
                if(r.FieldCount==0)continue;
                var columns=Enumerable.Range(0,r.FieldCount).Select(r.GetName).ToHashSet(StringComparer.OrdinalIgnoreCase);
                if(!new[]{"CODICTA","DESCCTA","TIPOCTA","HABILITARCTA","INDCPICTA"}.All(columns.Contains))
                {while(await r.ReadAsync(ct)){} continue;}
                found=true;
                while(await r.ReadAsync(ct))
                {
                    if(r["HABILITARCTA"] is DBNull||Convert.ToInt32(r["HABILITARCTA"])!=1||Convert.ToString(r["TIPOCTA"])?.Trim()!="D")continue;
                    var indicator=r["INDCPICTA"] is DBNull?0:Convert.ToInt32(r["INDCPICTA"]);
                    if(suppliers?indicator!=3:new[]{2,3,6}.Contains(indicator))continue;
                    accounts.Add(new(Convert.ToString(r["CODICTA"])!.Trim(),Convert.ToString(r["DESCCTA"])!.Trim()));
                }
            }while(await r.NextResultAsync(ct));
        }
        if(!found||Convert.ToInt32(status.Value)!=0)throw new ArgumentException("Zeus no devolvió el plan esperado de SpMae_Maecont (opción A). Revisa el procedimiento y sus permisos.");
        return accounts.DistinctBy(a=>a.Codigo,StringComparer.OrdinalIgnoreCase).OrderBy(a=>a.Codigo).ToArray();
    }
}

public sealed class ZeusWarehouseRepository(TenantConnectionFactory connections)
{
    public async Task<ZeusWarehouseConfig> GetAsync(long company,long warehouse,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"""
            SELECT z.Version,z.Servidor,z.BaseDatos,z.Configuracion FROM inv.Bodega b
            LEFT JOIN core.ZeusBodegaCuenta z ON z.EmpresaId=b.EmpresaId AND z.BodegaId=b.BodegaId
            WHERE b.EmpresaId=@E AND b.BodegaId=@B AND b.Activa=1;
            """,company);ZeusRepository.Add(q,"@B",warehouse);
        await using var r=await q.ExecuteReaderAsync(ct);
        if(!await r.ReadAsync(ct))throw new ArgumentException("La bodega no existe o está inactiva en esta empresa.");
        return r.IsDBNull(0)?new(0,"","",null):new(r.GetInt32(0),r.GetString(1),r.GetString(2),JsonSerializer.Deserialize<ZeusWarehouseAccounts>(r.GetString(3)));
    }
    public async Task SaveAsync(long company,long warehouse,long user,ZeusWarehouseSave input,ZeusSettingsRequest settings,CancellationToken ct)
    {
        if(input.Cuentas is null||input.Version<0||input.VersionEmpresa!=settings.Version)throw new ArgumentException("La configuración cambió. Cierra y vuelve a consultar la bodega.");
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        await using var q=ZeusRepository.Command(c,"""
            IF NOT EXISTS(SELECT 1 FROM core.ZeusConfiguracion WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND Version=@VE)
                THROW 51702,'La configuracion de empresa cambio; vuelve a consultar.',1;
            IF EXISTS(SELECT 1 FROM core.ZeusEnvio WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND Estado IN('PENDIENTE','ENVIANDO','INCIERTO'))
                THROW 51701,'Resuelve los envios pendientes o inciertos antes de cambiar cuentas.',1;
            IF NOT EXISTS(SELECT 1 FROM inv.Bodega WHERE EmpresaId=@E AND BodegaId=@B AND Activa=1)
                THROW 51702,'La bodega no existe o esta inactiva en esta empresa.',1;
            DECLARE @Actual int;
            SELECT @Actual=Version FROM core.ZeusBodegaCuenta WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND BodegaId=@B;
            IF ISNULL(@Actual,0)<>@V THROW 51702,'Las cuentas cambiaron; vuelve a consultar.',1;
            IF @Actual IS NULL INSERT core.ZeusBodegaCuenta(EmpresaId,BodegaId,Configuracion,Servidor,BaseDatos,ActualizadoPor) VALUES(@E,@B,@J,@S,@D,@U);
            ELSE UPDATE core.ZeusBodegaCuenta SET Configuracion=@J,Servidor=@S,BaseDatos=@D,Version=Version+1,ActualizadoPor=@U,ActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E AND BodegaId=@B;
            INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
            VALUES(@E,@U,'ZEUS_BODEGA_CONFIGURAR','inv.Bodega',CONVERT(nvarchar(100),@B),@J,'ZEUS');
            """,company,tx);
        ZeusRepository.Add(q,"@B",warehouse);ZeusRepository.Add(q,"@V",input.Version);ZeusRepository.Add(q,"@VE",input.VersionEmpresa);
        ZeusRepository.Add(q,"@S",settings.Configuracion.ServidorEsperado);ZeusRepository.Add(q,"@D",settings.Configuracion.BaseEsperada);
        ZeusRepository.Add(q,"@J",JsonSerializer.Serialize(input.Cuentas));ZeusRepository.Add(q,"@U",user);
        await q.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);
    }
}
