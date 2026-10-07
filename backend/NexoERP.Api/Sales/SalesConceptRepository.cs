using System.Data;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;
using NexoERP.Api.Zeus;

namespace NexoERP.Api.Sales;

public sealed record SalesConceptInput(string Codigo,string Nombre,string CuentaIngresoZeus,bool Activo,int Version);
public sealed record SalesConcept(long Id,string Codigo,string Nombre,string CuentaIngresoZeus,bool Activo,int Version);

public sealed class SalesConceptRepository(TenantConnectionFactory connections)
{
    public async Task<SalesConcept[]> ListAsync(long company,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"SELECT ConceptoVentaId,Codigo,Nombre,CuentaIngresoZeus,Activo,Version FROM ven.ConceptoVenta WHERE EmpresaId=@E ORDER BY Codigo",company);
        var result=new List<SalesConcept>();
        await using var r=await q.ExecuteReaderAsync(ct);
        while(await r.ReadAsync(ct))result.Add(new(r.GetInt64(0),r.GetString(1),r.GetString(2),r.GetString(3),r.GetBoolean(4),r.GetInt32(5)));
        return result.ToArray();
    }

    public async Task<SalesConcept> SaveAsync(long company,long? id,SalesConceptInput input,long user,ZeusSettings settings,CancellationToken ct)
    {
        var code=(input.Codigo??"").Trim().ToUpperInvariant();
        var name=(input.Nombre??"").Trim();
        var account=(input.CuentaIngresoZeus??"").Trim();
        if(code.Length is <1 or >30||code.Any(ch=>!(ch is >= 'A' and <= 'Z'||ch is >= '0' and <= '9'||ch is '_' or '-')))
            throw new ArgumentException("El código debe tener 1 a 30 caracteres: letras mayúsculas, números, guion o guion bajo.");
        if(name.Length is <1 or >120||name.Any(char.IsControl))throw new ArgumentException("Escribe el nombre del concepto (máximo 120 caracteres).");
        if(!account.StartsWith("4",StringComparison.Ordinal)||account.Length>16)
            throw new ArgumentException("Selecciona una cuenta de ingreso clase 4 de Zeus.");
        if(code=="FINANCIACION"&&!account.StartsWith("4135",StringComparison.Ordinal))
            throw new ArgumentException("La financiación debe usar una cuenta de ingreso 4135 de Zeus.");
        if(id is not null&&input.Version<1)throw new ArgumentException("Actualiza el maestro antes de editar este concepto.");
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        await using var q=ZeusRepository.Command(c,"SELECT Configuracion FROM core.ZeusConfiguracion WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E",company,tx);
        var config=await q.ExecuteScalarAsync(ct) as string;
        if(config is null)throw new ArgumentException("Configura la conexión Zeus de esta empresa.");
        // No guardar una cuenta obtenida de otra base Zeus si cambió el destino durante la edición.
        var current=System.Text.Json.JsonSerializer.Deserialize<ZeusSettings>(config)!;
        if(current.ServidorEsperado!=settings.ServidorEsperado||current.BaseEsperada!=settings.BaseEsperada)
            throw new ArgumentException("Cambió la conexión Zeus. Actualiza el plan de cuentas e intenta otra vez.");
        ZeusRepository.Add(q,"@Code",code);ZeusRepository.Add(q,"@Name",name);ZeusRepository.Add(q,"@Account",account);
        ZeusRepository.Add(q,"@Server",settings.ServidorEsperado);ZeusRepository.Add(q,"@Database",settings.BaseEsperada);
        ZeusRepository.Add(q,"@Active",input.Activo);ZeusRepository.Add(q,"@User",user);
        var creating=id is null;
        if(creating)
        {
            q.CommandText="INSERT ven.ConceptoVenta(EmpresaId,Codigo,Nombre,CuentaIngresoZeus,ServidorZeus,BaseDatosZeus,Activo,CreadoPor) OUTPUT inserted.ConceptoVentaId VALUES(@E,@Code,@Name,@Account,@Server,@Database,@Active,@User)";
            id=Convert.ToInt64(await q.ExecuteScalarAsync(ct));
        }
        else
        {
            ZeusRepository.Add(q,"@Id",id.GetValueOrDefault());ZeusRepository.Add(q,"@Version",input.Version);
            q.CommandText="UPDATE ven.ConceptoVenta SET Codigo=@Code,Nombre=@Name,CuentaIngresoZeus=@Account,ServidorZeus=@Server,BaseDatosZeus=@Database,Activo=@Active,Version=Version+1,ActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E AND ConceptoVentaId=@Id AND Version=@Version";
            if(await q.ExecuteNonQueryAsync(ct)!=1)throw new ArgumentException("El concepto cambió o ya no existe. Actualiza el maestro e intenta otra vez.");
        }
        await tx.CommitAsync(ct);
        return new(id.GetValueOrDefault(),code,name,account,input.Activo,creating?1:input.Version+1);
    }
}
