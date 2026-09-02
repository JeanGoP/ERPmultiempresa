using System.Data;
using System.Text.Json;
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
        command.CommandText="""
            SELECT TerceroId,TipoIdentificacion,NumeroIdentificacion,DigitoVerificacion,RazonSocial,
                   NombreComercial,CodigoResponsabilidadFiscal,RegimenFiscalCodigo,RegimenFiscalNombre,
                   Direccion,CiudadCodigo,Ciudad,DepartamentoCodigo,Departamento,CodigoPostal,PaisCodigo,Pais,
                   ContactoNombre,Telefono,Correo,SitioWeb,DatosXmlJson,Activo
            FROM ter.Tercero WHERE EmpresaId=@EmpresaId AND EsProveedor=1 ORDER BY RazonSocial;
            """;
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);
        await using var reader=await command.ExecuteReaderAsync(ct); var result=new List<SupplierResponse>();
        while(await reader.ReadAsync(ct)) result.Add(new(
            reader.GetInt64(0),reader.GetString(1),reader.GetString(2),reader.IsDBNull(3)?null:reader.GetString(3),reader.GetString(4),
            Text(reader,5),Text(reader,6),Text(reader,7),Text(reader,8),Text(reader,9),Text(reader,10),Text(reader,11),Text(reader,12),Text(reader,13),
            Text(reader,14),Text(reader,15),Text(reader,16),Text(reader,17),Text(reader,18),Text(reader,19),Text(reader,20),Text(reader,21),reader.GetBoolean(22)));
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

    public Task<MasterSaveResponse> SaveSupplierAsync(long e,SaveSupplierRequest r,CancellationToken ct,long? supplierId=null)=>ExecuteSaveAsync(e,"ter.usp_GuardarProveedor",r.UsuarioId,ct,c=>
    {
        Add(c,"@TerceroId",SqlDbType.BigInt,supplierId);Add(c,"@TipoIdentificacion",SqlDbType.VarChar,r.TipoIdentificacion,10);Add(c,"@NumeroIdentificacion",SqlDbType.NVarChar,r.NumeroIdentificacion,30);Add(c,"@DigitoVerificacion",SqlDbType.Char,r.DigitoVerificacion,1);Add(c,"@RazonSocial",SqlDbType.NVarChar,r.RazonSocial,200);
        Add(c,"@NombreComercial",SqlDbType.NVarChar,r.NombreComercial,200);Add(c,"@CodigoResponsabilidadFiscal",SqlDbType.NVarChar,r.CodigoResponsabilidadFiscal,100);Add(c,"@RegimenFiscalCodigo",SqlDbType.NVarChar,r.RegimenFiscalCodigo,20);Add(c,"@RegimenFiscalNombre",SqlDbType.NVarChar,r.RegimenFiscalNombre,100);
        Add(c,"@Direccion",SqlDbType.NVarChar,r.Direccion,300);Add(c,"@CiudadCodigo",SqlDbType.NVarChar,r.CiudadCodigo,20);Add(c,"@Ciudad",SqlDbType.NVarChar,r.Ciudad,100);Add(c,"@DepartamentoCodigo",SqlDbType.NVarChar,r.DepartamentoCodigo,20);Add(c,"@Departamento",SqlDbType.NVarChar,r.Departamento,100);Add(c,"@CodigoPostal",SqlDbType.NVarChar,r.CodigoPostal,20);Add(c,"@PaisCodigo",SqlDbType.NVarChar,r.PaisCodigo,10);Add(c,"@Pais",SqlDbType.NVarChar,r.Pais,100);
        Add(c,"@ContactoNombre",SqlDbType.NVarChar,r.ContactoNombre,150);Add(c,"@Telefono",SqlDbType.NVarChar,r.Telefono,50);Add(c,"@Correo",SqlDbType.NVarChar,r.Correo,254);Add(c,"@SitioWeb",SqlDbType.NVarChar,r.SitioWeb,300);Add(c,"@DatosXmlJson",SqlDbType.NVarChar,r.DatosXmlJson,-1);
    });

    public async Task DeleteSupplierAsync(long empresaId,long supplierId,long actorId,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,ct);
        await using var transaction=(SqlTransaction)await connection.BeginTransactionAsync(ct);
        string name; bool isClient;
        await using(var current=connection.CreateCommand())
        {
            current.Transaction=transaction;
            current.CommandText="SELECT RazonSocial,EsCliente FROM ter.Tercero WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND TerceroId=@TerceroId AND EsProveedor=1;";
            Add(current,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(current,"@TerceroId",SqlDbType.BigInt,supplierId);
            await using var reader=await current.ExecuteReaderAsync(ct);if(!await reader.ReadAsync(ct))throw new InvalidOperationException("El proveedor no existe en esta empresa.");name=reader.GetString(0);isClient=reader.GetBoolean(1);
        }
        if(await HasSupplierOperationalHistoryAsync(connection,transaction,supplierId,ct)) throw new InvalidOperationException("No se puede eliminar el proveedor porque tiene compras, pagos, movimientos u otro historial relacionado.");
        int removedMappings;
        await using(var mappings=connection.CreateCommand())
        {
            mappings.Transaction=transaction;mappings.CommandText="DELETE comp.HomologacionArticuloProveedor WHERE EmpresaId=@EmpresaId AND TerceroId=@TerceroId;";Add(mappings,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(mappings,"@TerceroId",SqlDbType.BigInt,supplierId);removedMappings=await mappings.ExecuteNonQueryAsync(ct);
        }
        await using(var command=connection.CreateCommand())
        {
            command.Transaction=transaction;command.CommandText=isClient
                ? "UPDATE ter.Tercero SET EsProveedor=0 WHERE EmpresaId=@EmpresaId AND TerceroId=@TerceroId AND EsProveedor=1;"
                : "DELETE ter.Tercero WHERE EmpresaId=@EmpresaId AND TerceroId=@TerceroId AND EsProveedor=1;";
            Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(command,"@TerceroId",SqlDbType.BigInt,supplierId);await command.ExecuteNonQueryAsync(ct);
        }
        await using(var audit=connection.CreateCommand())
        {
            audit.Transaction=transaction;audit.CommandText="INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@EmpresaId,@Actor,'PROVEEDOR_ELIMINADO','ter.Tercero',CONVERT(nvarchar(100),@TerceroId),@Valores,'MAESTROS');";
            Add(audit,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(audit,"@Actor",SqlDbType.BigInt,actorId);Add(audit,"@TerceroId",SqlDbType.BigInt,supplierId);Add(audit,"@Valores",SqlDbType.NVarChar,JsonSerializer.Serialize(new { RazonSocial=name,HomologacionesEliminadas=removedMappings,ConservadoComoCliente=isClient }));await audit.ExecuteNonQueryAsync(ct);
        }
        await transaction.CommitAsync(ct);
    }

    public Task<MasterSaveResponse> SaveUnitAsync(long e,SaveUnitRequest r,CancellationToken ct)=>ExecuteSaveAsync(e,"inv.usp_GuardarUnidadMedida",r.UsuarioId,ct,c=>{Add(c,"@Codigo",SqlDbType.NVarChar,r.Codigo,20);Add(c,"@Nombre",SqlDbType.NVarChar,r.Nombre,80);Add(c,"@Simbolo",SqlDbType.NVarChar,r.Simbolo,15);});
    public Task<MasterSaveResponse> SaveWarehouseAsync(long e,SaveWarehouseRequest r,CancellationToken ct)=>ExecuteSaveAsync(e,"inv.usp_GuardarBodega",r.UsuarioId,ct,c=>{Add(c,"@Codigo",SqlDbType.NVarChar,r.Codigo,30);Add(c,"@Nombre",SqlDbType.NVarChar,r.Nombre,120);Add(c,"@UsaUbicaciones",SqlDbType.Bit,r.UsaUbicaciones);Add(c,"@EsTransito",SqlDbType.Bit,r.EsTransito);});
    public Task<MasterSaveResponse> SaveArticleAsync(long e,SaveArticleRequest r,CancellationToken ct)=>ExecuteSaveAsync(e,"inv.usp_GuardarArticulo",r.UsuarioId,ct,c=>{Add(c,"@Codigo",SqlDbType.NVarChar,r.Codigo,50);Add(c,"@Descripcion",SqlDbType.NVarChar,r.Descripcion,300);Add(c,"@Tipo",SqlDbType.VarChar,r.Tipo,20);Add(c,"@UnidadBaseId",SqlDbType.BigInt,r.UnidadBaseId);Add(c,"@ManejaInventario",SqlDbType.Bit,r.ManejaInventario);Add(c,"@ManejaLote",SqlDbType.Bit,r.ManejaLote);Add(c,"@ManejaSerial",SqlDbType.Bit,r.ManejaSerial);Add(c,"@RequiereVencimiento",SqlDbType.Bit,r.RequiereVencimiento);AddDecimal(c,"@PesoBaseKg",r.PesoBaseKg,20,8);AddDecimal(c,"@VolumenBaseM3",r.VolumenBaseM3,20,10);});
    public Task<MasterSaveResponse> SaveArticleUnitAsync(long e,long articleId,SaveArticleUnitRequest r,CancellationToken ct)=>ExecuteSaveAsync(e,"inv.usp_GuardarArticuloUnidad",r.UsuarioId,ct,c=>{Add(c,"@ArticuloId",SqlDbType.BigInt,articleId);Add(c,"@UnidadMedidaId",SqlDbType.BigInt,r.UnidadMedidaId);AddDecimal(c,"@FactorAUnidadBase",r.FactorAUnidadBase,20,10);Add(c,"@EsUnidadCompra",SqlDbType.Bit,r.EsUnidadCompra);Add(c,"@EsUnidadVenta",SqlDbType.Bit,r.EsUnidadVenta);});
    public Task<MasterSaveResponse> SaveMappingAsync(long e,SaveItemMappingRequest r,CancellationToken ct)=>ExecuteSaveAsync(e,"comp.usp_GuardarHomologacionArticulo",r.UsuarioId,ct,c=>{Add(c,"@TerceroId",SqlDbType.BigInt,r.TerceroId);Add(c,"@CodigoExterno",SqlDbType.NVarChar,r.CodigoExterno,80);Add(c,"@DescripcionExterna",SqlDbType.NVarChar,r.DescripcionExterna,300);Add(c,"@ArticuloId",SqlDbType.BigInt,r.ArticuloId);Add(c,"@UnidadMedidaId",SqlDbType.BigInt,r.UnidadMedidaId);AddDecimal(c,"@FactorAUnidadBase",r.FactorAUnidadBase,20,10);});

    public async Task<MasterSaveResponse> UpdateArticleAsync(long empresaId,long articleId,SaveArticleRequest input,long actorId,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,ct);
        await using var transaction=(SqlTransaction)await connection.BeginTransactionAsync(ct);
        string oldType; long oldUnit; bool oldInventory; bool oldLot; bool oldSerial; bool oldExpiry;
        await using(var current=connection.CreateCommand())
        {
            current.Transaction=transaction;
            current.CommandText="SELECT Tipo,UnidadBaseId,ManejaInventario,ManejaLote,ManejaSerial,RequiereVencimiento FROM inv.Articulo WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId;";
            Add(current,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(current,"@ArticuloId",SqlDbType.BigInt,articleId);
            await using var reader=await current.ExecuteReaderAsync(ct);
            if(!await reader.ReadAsync(ct)) throw new InvalidOperationException("El artículo no existe en esta empresa.");
            oldType=reader.GetString(0);oldUnit=reader.GetInt64(1);oldInventory=reader.GetBoolean(2);oldLot=reader.GetBoolean(3);oldSerial=reader.GetBoolean(4);oldExpiry=reader.GetBoolean(5);
        }
        var hasReferences=await HasArticleReferencesAsync(connection,transaction,articleId,ct);
        var changesOperationalData=oldType!=input.Tipo||oldUnit!=input.UnidadBaseId||oldInventory!=input.ManejaInventario||oldLot!=input.ManejaLote||oldSerial!=input.ManejaSerial||oldExpiry!=input.RequiereVencimiento;
        if(hasReferences&&changesOperationalData) throw new InvalidOperationException("El artículo ya tiene relaciones o movimientos. Puedes editar su código y descripción, pero no su tipo, unidad base ni controles de inventario.");
        await using(var command=connection.CreateCommand())
        {
            command.Transaction=transaction;
            command.CommandText="UPDATE inv.Articulo SET Codigo=@Codigo,Descripcion=@Descripcion,Tipo=@Tipo,UnidadBaseId=@UnidadBaseId,ManejaInventario=@ManejaInventario,ManejaLote=@ManejaLote,ManejaSerial=@ManejaSerial,RequiereVencimiento=@RequiereVencimiento,PesoBaseKg=COALESCE(@PesoBaseKg,PesoBaseKg),VolumenBaseM3=COALESCE(@VolumenBaseM3,VolumenBaseM3) WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId;";
            Add(command,"@Codigo",SqlDbType.NVarChar,input.Codigo.Trim().ToUpperInvariant(),50);Add(command,"@Descripcion",SqlDbType.NVarChar,input.Descripcion.Trim(),300);Add(command,"@Tipo",SqlDbType.VarChar,input.Tipo,20);Add(command,"@UnidadBaseId",SqlDbType.BigInt,input.UnidadBaseId);Add(command,"@ManejaInventario",SqlDbType.Bit,input.ManejaInventario);Add(command,"@ManejaLote",SqlDbType.Bit,input.ManejaLote);Add(command,"@ManejaSerial",SqlDbType.Bit,input.ManejaSerial);Add(command,"@RequiereVencimiento",SqlDbType.Bit,input.RequiereVencimiento);AddDecimal(command,"@PesoBaseKg",input.PesoBaseKg,20,8);AddDecimal(command,"@VolumenBaseM3",input.VolumenBaseM3,20,10);Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(command,"@ArticuloId",SqlDbType.BigInt,articleId);
            await command.ExecuteNonQueryAsync(ct);
        }
        await AuditArticleAsync(connection,transaction,empresaId,actorId,"ARTICULO_ACTUALIZADO",articleId,new { input.Codigo,input.Descripcion,input.Tipo,input.UnidadBaseId,input.ManejaInventario,input.ManejaLote,input.ManejaSerial,input.RequiereVencimiento },ct);
        await transaction.CommitAsync(ct);
        return new(articleId,false);
    }

    public async Task DeleteArticleAsync(long empresaId,long articleId,long actorId,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,ct);
        await using var transaction=(SqlTransaction)await connection.BeginTransactionAsync(ct);
        string code;
        await using(var current=connection.CreateCommand())
        {
            current.Transaction=transaction;current.CommandText="SELECT Codigo FROM inv.Articulo WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId;";Add(current,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(current,"@ArticuloId",SqlDbType.BigInt,articleId);
            var value=await current.ExecuteScalarAsync(ct);if(value is null)throw new InvalidOperationException("El artículo no existe en esta empresa.");code=Convert.ToString(value)!;
        }
        if(await HasArticleOperationalHistoryAsync(connection,transaction,articleId,ct)) throw new InvalidOperationException("No se puede eliminar el artículo porque tiene documentos, movimientos, saldos, lotes, seriales u otro historial operativo relacionado.");
        int removedMappings;
        await using(var mappings=connection.CreateCommand())
        {
            mappings.Transaction=transaction;mappings.CommandText="DELETE comp.HomologacionArticuloProveedor WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId;";Add(mappings,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(mappings,"@ArticuloId",SqlDbType.BigInt,articleId);removedMappings=await mappings.ExecuteNonQueryAsync(ct);
        }
        int removedConversions;
        await using(var conversions=connection.CreateCommand())
        {
            conversions.Transaction=transaction;conversions.CommandText="DELETE inv.ArticuloUnidad WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId;";Add(conversions,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(conversions,"@ArticuloId",SqlDbType.BigInt,articleId);removedConversions=await conversions.ExecuteNonQueryAsync(ct);
        }
        await using(var command=connection.CreateCommand()){command.Transaction=transaction;command.CommandText="DELETE inv.Articulo WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId;";Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(command,"@ArticuloId",SqlDbType.BigInt,articleId);await command.ExecuteNonQueryAsync(ct);}
        await AuditArticleAsync(connection,transaction,empresaId,actorId,"ARTICULO_ELIMINADO",articleId,new { Codigo=code,HomologacionesEliminadas=removedMappings,ConversionesEliminadas=removedConversions },ct);
        await transaction.CommitAsync(ct);
    }

    private static async Task<bool> HasArticleOperationalHistoryAsync(SqlConnection connection,SqlTransaction transaction,long articleId,CancellationToken ct)
    {
        await using var command=connection.CreateCommand();command.Transaction=transaction;
        command.CommandText="""
            DECLARE @Sql nvarchar(max)=N'',@HasHistory bit=0;
            SELECT @Sql=STRING_AGG(CONVERT(nvarchar(max),N'IF EXISTS(SELECT 1 FROM '+QUOTENAME(SCHEMA_NAME(t.schema_id))+N'.'+QUOTENAME(t.name)+N' WHERE '+QUOTENAME(c.name)+N'=@ArticleId) SET @HasHistory=1;'),NCHAR(10))
            FROM sys.tables t
            JOIN sys.columns c ON c.object_id=t.object_id AND c.name=N'ArticuloId'
            WHERE t.object_id<>OBJECT_ID(N'inv.Articulo')
              AND NOT(SCHEMA_NAME(t.schema_id)=N'inv' AND t.name=N'ArticuloUnidad')
              AND NOT(SCHEMA_NAME(t.schema_id)=N'comp' AND t.name=N'HomologacionArticuloProveedor');
            IF NULLIF(@Sql,N'') IS NOT NULL EXEC sys.sp_executesql @Sql,N'@ArticleId bigint,@HasHistory bit OUTPUT',@ArticleId,@HasHistory OUTPUT;
            SELECT @HasHistory;
            """;
        Add(command,"@ArticleId",SqlDbType.BigInt,articleId);
        return Convert.ToBoolean(await command.ExecuteScalarAsync(ct));
    }

    private static async Task<bool> HasSupplierOperationalHistoryAsync(SqlConnection connection,SqlTransaction transaction,long supplierId,CancellationToken ct)
    {
        await using var command=connection.CreateCommand();command.Transaction=transaction;
        command.CommandText="""
            DECLARE @Sql nvarchar(max)=N'',@HasHistory bit=0;
            SELECT @Sql=STRING_AGG(CONVERT(nvarchar(max),N'IF EXISTS(SELECT 1 FROM '+QUOTENAME(SCHEMA_NAME(t.schema_id))+N'.'+QUOTENAME(t.name)+N' WHERE '+QUOTENAME(c.name)+N'=@SupplierId) SET @HasHistory=1;'),NCHAR(10))
            FROM sys.foreign_key_columns fkc
            JOIN sys.tables t ON t.object_id=fkc.parent_object_id
            JOIN sys.columns c ON c.object_id=fkc.parent_object_id AND c.column_id=fkc.parent_column_id
            JOIN sys.columns referenced ON referenced.object_id=fkc.referenced_object_id AND referenced.column_id=fkc.referenced_column_id
            WHERE fkc.referenced_object_id=OBJECT_ID(N'ter.Tercero') AND referenced.name=N'TerceroId'
              AND NOT(SCHEMA_NAME(t.schema_id)=N'comp' AND t.name=N'HomologacionArticuloProveedor');
            IF NULLIF(@Sql,N'') IS NOT NULL EXEC sys.sp_executesql @Sql,N'@SupplierId bigint,@HasHistory bit OUTPUT',@SupplierId,@HasHistory OUTPUT;
            SELECT @HasHistory;
            """;
        Add(command,"@SupplierId",SqlDbType.BigInt,supplierId);
        return Convert.ToBoolean(await command.ExecuteScalarAsync(ct));
    }

    private static async Task<bool> HasArticleReferencesAsync(SqlConnection connection,SqlTransaction transaction,long articleId,CancellationToken ct)
    {
        await using var command=connection.CreateCommand();command.Transaction=transaction;
        command.CommandText="""
            DECLARE @Sql nvarchar(max)=N'',@HasReferences bit=0;
            SELECT @Sql=STRING_AGG(CONVERT(nvarchar(max),N'IF EXISTS(SELECT 1 FROM '+QUOTENAME(SCHEMA_NAME(t.schema_id))+N'.'+QUOTENAME(t.name)+N' WHERE '+QUOTENAME(c.name)+N'=@ArticleId) SET @HasReferences=1;'),NCHAR(10))
            FROM sys.foreign_key_columns fkc
            JOIN sys.tables t ON t.object_id=fkc.parent_object_id
            JOIN sys.columns c ON c.object_id=fkc.parent_object_id AND c.column_id=fkc.parent_column_id
            JOIN sys.columns referenced ON referenced.object_id=fkc.referenced_object_id AND referenced.column_id=fkc.referenced_column_id
            WHERE fkc.referenced_object_id=OBJECT_ID(N'inv.Articulo') AND referenced.name=N'ArticuloId';
            IF NULLIF(@Sql,N'') IS NOT NULL EXEC sys.sp_executesql @Sql,N'@ArticleId bigint,@HasReferences bit OUTPUT',@ArticleId,@HasReferences OUTPUT;
            SELECT @HasReferences;
            """;
        Add(command,"@ArticleId",SqlDbType.BigInt,articleId);
        return Convert.ToBoolean(await command.ExecuteScalarAsync(ct));
    }

    private static async Task AuditArticleAsync(SqlConnection connection,SqlTransaction transaction,long empresaId,long actorId,string operation,long articleId,object values,CancellationToken ct)
    {
        await using var command=connection.CreateCommand();command.Transaction=transaction;
        command.CommandText="INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@EmpresaId,@Actor,@Operacion,'inv.Articulo',CONVERT(nvarchar(100),@ArticuloId),@Valores,'MAESTROS');";
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(command,"@Actor",SqlDbType.BigInt,actorId);Add(command,"@Operacion",SqlDbType.VarChar,operation,80);Add(command,"@ArticuloId",SqlDbType.BigInt,articleId);Add(command,"@Valores",SqlDbType.NVarChar,JsonSerializer.Serialize(values));
        await command.ExecuteNonQueryAsync(ct);
    }

    private async Task<MasterSaveResponse> ExecuteSaveAsync(long e,string procedure,long? userId,CancellationToken ct,Action<SqlCommand> parameters)
    {
        await using var connection=await connections.OpenAsync(e,false,ct); await using var command=connection.CreateCommand(); command.CommandType=CommandType.StoredProcedure; command.CommandText=procedure;
        Add(command,"@EmpresaId",SqlDbType.BigInt,e); parameters(command); Add(command,"@UsuarioId",SqlDbType.BigInt,userId);
        await using var reader=await command.ExecuteReaderAsync(ct); if(!await reader.ReadAsync(ct)) throw new InvalidOperationException("La operación maestra no devolvió resultado."); return new(reader.GetInt64(0),reader.GetBoolean(1));
    }
    private static string? Text(SqlDataReader reader,int ordinal)=>reader.IsDBNull(ordinal)?null:reader.GetString(ordinal);
    private static void Add(SqlCommand c,string name,SqlDbType type,object? value,int size=0){var p=size>0?new SqlParameter(name,type,size):new SqlParameter(name,type);p.Value=value??DBNull.Value;c.Parameters.Add(p);}
    private static void AddDecimal(SqlCommand c,string name,decimal? value,byte precision,byte scale)=>c.Parameters.Add(new SqlParameter(name,SqlDbType.Decimal){Precision=precision,Scale=scale,Value=value is null?DBNull.Value:value.Value});
}
