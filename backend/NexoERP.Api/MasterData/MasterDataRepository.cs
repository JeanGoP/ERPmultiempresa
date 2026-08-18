using System.Data;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;
using NexoERP.Api.Inventory;

namespace NexoERP.Api.MasterData;

public sealed class MasterDataRepository(TenantConnectionFactory connections)
{
    public async Task<IReadOnlyList<SupplierResponse>> GetSuppliersAsync(long empresaId,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,ct);
        await using var command=connection.CreateCommand();
        command.CommandText="SELECT TerceroId,TipoIdentificacion,NumeroIdentificacion,DigitoVerificacion,RazonSocial,Activo FROM ter.Tercero WHERE EmpresaId=@EmpresaId AND EsProveedor=1 ORDER BY RazonSocial;";
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);
        await using var reader=await command.ExecuteReaderAsync(ct); var result=new List<SupplierResponse>();
        while(await reader.ReadAsync(ct)) result.Add(new(reader.GetInt64(0),reader.GetString(1),reader.GetString(2),reader.IsDBNull(3)?null:reader.GetString(3),reader.GetString(4),reader.GetBoolean(5)));
        return result;
    }

    public async Task<IReadOnlyList<UnitOfMeasureResponse>> GetUnitsAsync(long empresaId,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,ct); await using var command=connection.CreateCommand();
        command.CommandText="SELECT UnidadMedidaId,Codigo,Nombre,Simbolo,Activa FROM inv.UnidadMedida WHERE EmpresaId=@EmpresaId ORDER BY Codigo;"; Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);
        await using var reader=await command.ExecuteReaderAsync(ct); var result=new List<UnitOfMeasureResponse>();
        while(await reader.ReadAsync(ct)) result.Add(new(reader.GetInt64(0),reader.GetString(1),reader.GetString(2),reader.GetString(3),reader.GetBoolean(4))); return result;
    }

    public async Task<IReadOnlyList<ArticleResponse>> GetArticlesAsync(long empresaId,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,ct); await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT a.ArticuloId,a.Codigo,a.Descripcion,a.Tipo,a.ManejaInventario,a.UnidadBaseId,u.Codigo,a.ManejaLote,a.ManejaSerial,a.RequiereVencimiento,a.PesoBaseKg,a.VolumenBaseM3,a.Activo
            FROM inv.Articulo a JOIN inv.UnidadMedida u ON u.EmpresaId=a.EmpresaId AND u.UnidadMedidaId=a.UnidadBaseId
            WHERE a.EmpresaId=@EmpresaId ORDER BY a.Codigo;
            """; Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);
        await using var reader=await command.ExecuteReaderAsync(ct); var result=new List<ArticleResponse>();
        while(await reader.ReadAsync(ct)) result.Add(new(reader.GetInt64(0),reader.GetString(1),reader.GetString(2),reader.GetString(3),reader.GetBoolean(4),reader.GetInt64(5),reader.GetString(6),reader.GetBoolean(7),reader.GetBoolean(8),reader.GetBoolean(9),reader.IsDBNull(10)?null:reader.GetDecimal(10),reader.IsDBNull(11)?null:reader.GetDecimal(11),reader.GetBoolean(12))); return result;
    }

    public async Task<IReadOnlyList<ItemMappingResponse>> GetMappingsAsync(long empresaId,long? terceroId,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,ct); await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT h.HomologacionArticuloProveedorId,h.TerceroId,t.NumeroIdentificacion,t.RazonSocial,h.CodigoExterno,h.DescripcionExterna,h.ArticuloId,a.Codigo,a.Descripcion,u.Codigo,h.FactorAUnidadBase,h.Activa
            FROM comp.HomologacionArticuloProveedor h
            JOIN ter.Tercero t ON t.EmpresaId=h.EmpresaId AND t.TerceroId=h.TerceroId
            JOIN inv.Articulo a ON a.EmpresaId=h.EmpresaId AND a.ArticuloId=h.ArticuloId
            LEFT JOIN inv.UnidadMedida u ON u.EmpresaId=h.EmpresaId AND u.UnidadMedidaId=h.UnidadMedidaId
            WHERE h.EmpresaId=@EmpresaId AND (@TerceroId IS NULL OR h.TerceroId=@TerceroId)
            ORDER BY t.RazonSocial,h.CodigoExterno;
            """; Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId); Add(command,"@TerceroId",SqlDbType.BigInt,terceroId);
        await using var reader=await command.ExecuteReaderAsync(ct); var result=new List<ItemMappingResponse>();
        while(await reader.ReadAsync(ct)) result.Add(new(reader.GetInt64(0),reader.GetInt64(1),reader.GetString(2),reader.GetString(3),reader.GetString(4),reader.IsDBNull(5)?null:reader.GetString(5),reader.GetInt64(6),reader.GetString(7),reader.GetString(8),reader.IsDBNull(9)?null:reader.GetString(9),reader.GetDecimal(10),reader.GetBoolean(11))); return result;
    }

    public Task<MasterSaveResponse> SaveSupplierAsync(long e,SaveSupplierRequest r,CancellationToken ct)=>ExecuteSaveAsync(e,"ter.usp_GuardarProveedor",r.UsuarioId,ct,c=>{Add(c,"@TipoIdentificacion",SqlDbType.VarChar,r.TipoIdentificacion,10);Add(c,"@NumeroIdentificacion",SqlDbType.NVarChar,r.NumeroIdentificacion,30);Add(c,"@DigitoVerificacion",SqlDbType.Char,r.DigitoVerificacion,1);Add(c,"@RazonSocial",SqlDbType.NVarChar,r.RazonSocial,200);});
    public Task<MasterSaveResponse> SaveUnitAsync(long e,SaveUnitRequest r,CancellationToken ct)=>ExecuteSaveAsync(e,"inv.usp_GuardarUnidadMedida",r.UsuarioId,ct,c=>{Add(c,"@Codigo",SqlDbType.NVarChar,r.Codigo,20);Add(c,"@Nombre",SqlDbType.NVarChar,r.Nombre,80);Add(c,"@Simbolo",SqlDbType.NVarChar,r.Simbolo,15);});
    public Task<MasterSaveResponse> SaveWarehouseAsync(long e,SaveWarehouseRequest r,CancellationToken ct)=>ExecuteSaveAsync(e,"inv.usp_GuardarBodega",r.UsuarioId,ct,c=>{Add(c,"@Codigo",SqlDbType.NVarChar,r.Codigo,30);Add(c,"@Nombre",SqlDbType.NVarChar,r.Nombre,120);Add(c,"@UsaUbicaciones",SqlDbType.Bit,r.UsaUbicaciones);Add(c,"@EsTransito",SqlDbType.Bit,r.EsTransito);});
    public Task<MasterSaveResponse> SaveArticleAsync(long e,SaveArticleRequest r,CancellationToken ct)=>ExecuteSaveAsync(e,"inv.usp_GuardarArticulo",r.UsuarioId,ct,c=>{Add(c,"@Codigo",SqlDbType.NVarChar,r.Codigo,50);Add(c,"@Descripcion",SqlDbType.NVarChar,r.Descripcion,300);Add(c,"@Tipo",SqlDbType.VarChar,r.Tipo,20);Add(c,"@UnidadBaseId",SqlDbType.BigInt,r.UnidadBaseId);Add(c,"@ManejaInventario",SqlDbType.Bit,r.ManejaInventario);Add(c,"@ManejaLote",SqlDbType.Bit,r.ManejaLote);Add(c,"@ManejaSerial",SqlDbType.Bit,r.ManejaSerial);Add(c,"@RequiereVencimiento",SqlDbType.Bit,r.RequiereVencimiento);AddDecimal(c,"@PesoBaseKg",r.PesoBaseKg,20,8);AddDecimal(c,"@VolumenBaseM3",r.VolumenBaseM3,20,10);});
    public Task<MasterSaveResponse> SaveArticleUnitAsync(long e,long articleId,SaveArticleUnitRequest r,CancellationToken ct)=>ExecuteSaveAsync(e,"inv.usp_GuardarArticuloUnidad",r.UsuarioId,ct,c=>{Add(c,"@ArticuloId",SqlDbType.BigInt,articleId);Add(c,"@UnidadMedidaId",SqlDbType.BigInt,r.UnidadMedidaId);AddDecimal(c,"@FactorAUnidadBase",r.FactorAUnidadBase,20,10);Add(c,"@EsUnidadCompra",SqlDbType.Bit,r.EsUnidadCompra);Add(c,"@EsUnidadVenta",SqlDbType.Bit,r.EsUnidadVenta);});
    public Task<MasterSaveResponse> SaveMappingAsync(long e,SaveItemMappingRequest r,CancellationToken ct)=>ExecuteSaveAsync(e,"comp.usp_GuardarHomologacionArticulo",r.UsuarioId,ct,c=>{Add(c,"@TerceroId",SqlDbType.BigInt,r.TerceroId);Add(c,"@CodigoExterno",SqlDbType.NVarChar,r.CodigoExterno,80);Add(c,"@DescripcionExterna",SqlDbType.NVarChar,r.DescripcionExterna,300);Add(c,"@ArticuloId",SqlDbType.BigInt,r.ArticuloId);Add(c,"@UnidadMedidaId",SqlDbType.BigInt,r.UnidadMedidaId);AddDecimal(c,"@FactorAUnidadBase",r.FactorAUnidadBase,20,10);});

    private async Task<MasterSaveResponse> ExecuteSaveAsync(long e,string procedure,long? userId,CancellationToken ct,Action<SqlCommand> parameters)
    {
        await using var connection=await connections.OpenAsync(e,false,ct); await using var command=connection.CreateCommand(); command.CommandType=CommandType.StoredProcedure; command.CommandText=procedure;
        Add(command,"@EmpresaId",SqlDbType.BigInt,e); parameters(command); Add(command,"@UsuarioId",SqlDbType.BigInt,userId);
        await using var reader=await command.ExecuteReaderAsync(ct); if(!await reader.ReadAsync(ct)) throw new InvalidOperationException("La operación maestra no devolvió resultado."); return new(reader.GetInt64(0),reader.GetBoolean(1));
    }
    private static void Add(SqlCommand c,string name,SqlDbType type,object? value,int size=0){var p=size>0?new SqlParameter(name,type,size):new SqlParameter(name,type);p.Value=value??DBNull.Value;c.Parameters.Add(p);}
    private static void AddDecimal(SqlCommand c,string name,decimal? value,byte precision,byte scale)=>c.Parameters.Add(new SqlParameter(name,SqlDbType.Decimal){Precision=precision,Scale=scale,Value=value is null?DBNull.Value:value.Value});
}
