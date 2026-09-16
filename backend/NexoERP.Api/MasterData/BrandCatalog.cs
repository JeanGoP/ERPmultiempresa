using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;

namespace NexoERP.Api.MasterData;

public sealed record BrandResponse(long Id,string Nombre,bool Activa,int Referencias);
public sealed record SaveBrandRequest(string Nombre,bool Activa);
public sealed record RecognizeBrandsRequest(string[] Descripciones,string?[]? Codigos=null);
public sealed record RecognizedBrandResponse(int Indice,string? Marca);

public sealed class BrandCatalogRepository(TenantConnectionFactory connections)
{
    public async Task<List<BrandResponse>> ListAsync(long empresaId,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,ct);
        await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT m.MarcaId,m.Nombre,m.Activa,COUNT(c.CatalogoMarcaDescripcionId)
            FROM inv.Marca m LEFT JOIN inv.CatalogoMarcaDescripcion c ON c.EmpresaId=m.EmpresaId AND c.MarcaId=m.MarcaId
            WHERE m.EmpresaId=@EmpresaId GROUP BY m.MarcaId,m.Nombre,m.Activa ORDER BY m.Nombre;
            """;
        command.Parameters.Add("@EmpresaId",SqlDbType.BigInt).Value=empresaId;
        await using var reader=await command.ExecuteReaderAsync(ct);
        var result=new List<BrandResponse>();
        while(await reader.ReadAsync(ct))result.Add(new(reader.GetInt64(0),reader.GetString(1),reader.GetBoolean(2),reader.GetInt32(3)));
        return result;
    }

    public async Task<long> SaveAsync(long empresaId,long? id,SaveBrandRequest input,long actor,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,ct);
        await using var command=connection.CreateCommand();
        command.CommandText="""
            SET XACT_ABORT ON;
            BEGIN TRANSACTION;
            IF @Id IS NULL BEGIN
                INSERT inv.Marca(EmpresaId,Nombre,Activa) VALUES(@EmpresaId,@Nombre,@Activa);
                SET @Id=SCOPE_IDENTITY();
            END ELSE BEGIN
                UPDATE inv.Marca SET Nombre=@Nombre,Activa=@Activa WHERE EmpresaId=@EmpresaId AND MarcaId=@Id;
                IF @@ROWCOUNT=0 THROW 51630,'Marca no encontrada en esta empresa.',1;
            END;
            INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
            VALUES(@EmpresaId,@Actor,'GUARDAR_MARCA','inv.Marca',CONVERT(nvarchar(100),@Id),@Json,'MAESTROS');
            COMMIT;
            SELECT @Id;
            """;
        command.Parameters.Add("@EmpresaId",SqlDbType.BigInt).Value=empresaId;
        command.Parameters.Add("@Id",SqlDbType.BigInt).Value=(object?)id??DBNull.Value;
        command.Parameters.Add("@Nombre",SqlDbType.NVarChar,100).Value=input.Nombre.Trim();
        command.Parameters.Add("@Activa",SqlDbType.Bit).Value=input.Activa;
        command.Parameters.Add("@Actor",SqlDbType.BigInt).Value=actor;
        command.Parameters.Add("@Json",SqlDbType.NVarChar,-1).Value=JsonSerializer.Serialize(input);
        return Convert.ToInt64(await command.ExecuteScalarAsync(ct));
    }

    public async Task<List<RecognizedBrandResponse>> RecognizeAsync(long empresaId,string[] descriptions,string?[]? codes,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,ct);
        await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT CONVERT(int,j.[key]),m.Marca FROM OPENJSON(@Json) j
            LEFT JOIN OPENJSON(@Codigos) c ON c.[key]=j.[key]
            OUTER APPLY inv.fn_MarcaPorReferenciaDescripcion(@EmpresaId,CONVERT(nvarchar(100),c.value),CONVERT(nvarchar(300),j.value)) m ORDER BY CONVERT(int,j.[key]);
            """;
        command.Parameters.Add("@EmpresaId",SqlDbType.BigInt).Value=empresaId;
        command.Parameters.Add("@Json",SqlDbType.NVarChar,-1).Value=JsonSerializer.Serialize(descriptions);
        command.Parameters.Add("@Codigos",SqlDbType.NVarChar,-1).Value=JsonSerializer.Serialize(codes??[]);
        await using var reader=await command.ExecuteReaderAsync(ct);
        var result=new List<RecognizedBrandResponse>();
        while(await reader.ReadAsync(ct))result.Add(new(reader.GetInt32(0),reader.IsDBNull(1)?null:reader.GetString(1)));
        return result;
    }
}
