using System.Data;

namespace NexoERP.Api.Zeus;

public sealed record ZeusCostCenter(string Codigo,string Nombre);
public sealed record ZeusAccountingDimensions(ZeusCostCenter[] CentrosCosto,string[] CuentasRequierenCentroCosto);

public sealed partial class ZeusTransport
{
    public async Task<ZeusAccountingDimensions> AccountingDimensionsAsync(long company,ZeusSettings settings,CancellationToken ct)
    {
        await using var c=await OpenAsync(company,settings,ct);
        await using var q=c.CreateCommand();
        q.CommandType=CommandType.Text;
        q.CommandText="""
            SELECT RTRIM(IDCENCO),RTRIM(DESCENCO) FROM dbo.MAECCO
            WHERE TIPOCENCO='D' AND Deshabilitado=0 ORDER BY IDCENCO;
            SELECT RTRIM(CODICTA) FROM dbo.MAECONT
            WHERE HABILITARCTA=1 AND TIPOCTA='D' AND INDCCOCTA=1;
            """;
        var centers=new List<ZeusCostCenter>();var accounts=new List<string>();
        await using var r=await q.ExecuteReaderAsync(ct);
        while(await r.ReadAsync(ct))centers.Add(new(r.GetString(0),r.GetString(1)));
        await r.NextResultAsync(ct);
        while(await r.ReadAsync(ct))accounts.Add(r.GetString(0));
        return new(centers.ToArray(),accounts.ToArray());
    }
}
