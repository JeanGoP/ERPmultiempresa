using System.Data;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;
using NexoERP.Api.Zeus;

namespace NexoERP.Api.Sales;

public sealed record PortfolioTypeInput(string Codigo,string Nombre,bool Activo,int Version);
public sealed record PortfolioType(long Id,string Codigo,string Nombre,bool Activo,int Version);

public sealed class PortfolioTypeRepository(TenantConnectionFactory connections)
{
    public async Task<PortfolioType[]> ListAsync(long company,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"SELECT TipoCarteraId,Codigo,Nombre,Activo,Version FROM ven.TipoCartera WHERE EmpresaId=@E ORDER BY Nombre,Codigo",company);
        var items=new List<PortfolioType>();
        await using var r=await q.ExecuteReaderAsync(ct);
        while(await r.ReadAsync(ct))items.Add(new(r.GetInt64(0),r.GetString(1),r.GetString(2),r.GetBoolean(3),r.GetInt32(4)));
        return items.ToArray();
    }

    public async Task<PortfolioType> SaveAsync(long company,long? id,PortfolioTypeInput input,CancellationToken ct)
    {
        var code=(input.Codigo??"").Trim().ToUpperInvariant();
        var name=(input.Nombre??"").Trim();
        if(code.Length is <1 or >20||code.Any(ch=>!(ch is >= 'A' and <= 'Z'||ch is >= '0' and <= '9'||ch is '_' or '-')))
            throw new ArgumentException("El código debe tener 1 a 20 caracteres: letras, números, guion o guion bajo.");
        if(name.Length is <1 or >80||name.Any(char.IsControl))throw new ArgumentException("Escribe un nombre de máximo 80 caracteres.");
        if(code=="SIN_CLASIFICAR"&&input.Activo)throw new ArgumentException("Sin clasificar es una categoría reservada y no se ofrece al facturar.");
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        await using var q=ZeusRepository.Command(c,"",company,tx);
        ZeusRepository.Add(q,"@Code",code);ZeusRepository.Add(q,"@Name",name);ZeusRepository.Add(q,"@Active",input.Activo);
        if(id is null)
        {
            q.CommandText="INSERT ven.TipoCartera(EmpresaId,Codigo,Nombre,Activo) OUTPUT inserted.TipoCarteraId VALUES(@E,@Code,@Name,@Active)";
            id=Convert.ToInt64(await q.ExecuteScalarAsync(ct));
        }
        else
        {
            if(input.Version<1)throw new ArgumentException("Actualiza el maestro antes de editar este tipo.");
            ZeusRepository.Add(q,"@Id",id.Value);ZeusRepository.Add(q,"@Version",input.Version);
            q.CommandText="UPDATE ven.TipoCartera SET Nombre=@Name,Activo=@Active,Version=Version+1,ActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E AND TipoCarteraId=@Id AND Codigo=@Code AND Version=@Version";
            if(await q.ExecuteNonQueryAsync(ct)!=1)throw new ArgumentException("El tipo cambió, su código no puede modificarse o ya no existe. Actualiza el maestro.");
        }
        await tx.CommitAsync(ct);
        return new(id.Value,code,name,input.Activo,id.HasValue&&input.Version>0?input.Version+1:1);
    }
}
