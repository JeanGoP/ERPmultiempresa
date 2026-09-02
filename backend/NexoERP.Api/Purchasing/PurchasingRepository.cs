using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;

namespace NexoERP.Api.Purchasing;

public sealed class PurchasingRepository(TenantConnectionFactory connections)
{
    private static readonly IReadOnlyDictionary<string, string> Classifications = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        ["inventory"] = "INVENTARIO",
        ["service"] = "SERVICIO_GASTO",
        ["acquisition-cost"] = "COSTO_ADQUISICION",
        ["fixed-asset"] = "ACTIVO_FIJO",
        ["INVENTARIO"] = "INVENTARIO",
        ["SERVICIO_GASTO"] = "SERVICIO_GASTO",
        ["COSTO_ADQUISICION"] = "COSTO_ADQUISICION",
        ["ACTIVO_FIJO"] = "ACTIVO_FIJO"
    };

    public async Task<SupplierDocumentResponse> CreateDocumentAsync(long empresaId, CreateSupplierDocumentRequest input, CancellationToken cancellationToken)
    {
        var linePayload = input.Lineas.Select(line => new Dictionary<string, object?>
        {
            ["numeroLinea"] = line.NumeroLinea,
            ["articuloId"] = line.ArticuloId,
            ["codigoExterno"] = line.CodigoExterno,
            ["descripcion"] = line.Descripcion,
            ["clasificacion"] = MapClassification(line.Clasificacion),
            ["cantidad"] = line.Cantidad,
            ["unidadMedidaId"] = line.UnidadMedidaId,
            ["unidadCodigo"] = line.UnidadCodigo,
            ["manejaSerial"] = line.ManejaSerial || (line.Seriales?.Count > 0),
            ["factorAUnidadBase"] = line.FactorAUnidadBase,
            ["precioUnitario"] = line.PrecioUnitario,
            ["subtotalBruto"] = line.SubtotalBruto,
            ["descuento"] = line.Descuento,
            ["impuesto"] = line.Impuesto,
            ["cargo"] = line.Cargo,
            ["retencion"] = line.Retencion,
            ["totalNeto"] = line.TotalNeto
        }).ToArray();
        var serialPayload = input.Lineas.SelectMany(line => (line.Seriales ?? []).Select(serial => new Dictionary<string, object?>
        {
            ["numeroLinea"] = line.NumeroLinea,
            ["numeroUnidad"] = serial.NumeroUnidad,
            ["serial"] = serial.Serial,
            ["motor"] = serial.Motor,
            ["chasis"] = serial.Chasis,
            ["vin"] = serial.Vin,
            ["color"] = serial.Color,
            ["modelo"] = serial.Modelo,
            ["informacionOriginal"] = serial.InformacionOriginal
        })).ToArray();
        var tracePayload = input.Lineas.Where(line=>!string.IsNullOrWhiteSpace(line.NumeroLote)||line.FechaVencimiento is not null).Select(line=>new Dictionary<string,object?>
        {
            ["numeroLinea"]=line.NumeroLinea,
            ["numeroLote"]=line.NumeroLote,
            ["fechaVencimiento"]=line.FechaVencimiento?.ToString("yyyy-MM-dd")
        }).ToArray();
        var retentionPayload=input.Lineas.Where(line=>line.Retencion>0).Select(line=>new Dictionary<string,object?>
        {
            ["numeroLinea"]=line.NumeroLinea,
            ["retencion"]=line.Retencion
        }).ToArray();
        var hashXml = input.XmlOriginal is null ? null : Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(input.XmlOriginal))).ToLowerInvariant();

        await using var connection = await connections.OpenAsync(empresaId, false, cancellationToken);
        await using (var existing=connection.CreateCommand())
        {
            existing.CommandText="""
                SELECT TOP(1) d.DocumentoProveedorId
                FROM comp.DocumentoProveedor d
                JOIN ter.Tercero t ON t.EmpresaId=d.EmpresaId AND t.TerceroId=d.TerceroId
                WHERE d.EmpresaId=@EmpresaId AND
                (
                    (t.NumeroIdentificacion=@ProveedorIdentificacion AND d.TipoDocumento=@TipoDocumento AND d.NumeroDocumento=@NumeroDocumento)
                    OR (@CufeCude IS NOT NULL AND d.CufeCude=@CufeCude)
                    OR (@HashXml IS NOT NULL AND d.HashXml=@HashXml)
                );
                """;
            Add(existing,"@EmpresaId",SqlDbType.BigInt,empresaId);
            Add(existing,"@ProveedorIdentificacion",SqlDbType.NVarChar,input.ProveedorIdentificacion,30);
            Add(existing,"@TipoDocumento",SqlDbType.VarChar,input.TipoDocumento,20);
            Add(existing,"@NumeroDocumento",SqlDbType.NVarChar,input.NumeroDocumento,50);
            Add(existing,"@CufeCude",SqlDbType.NVarChar,input.CufeCude,120);
            Add(existing,"@HashXml",SqlDbType.Char,hashXml,64);
            var existingId=await existing.ExecuteScalarAsync(cancellationToken);
            if(existingId is not null and not DBNull) return new(Convert.ToInt64(existingId),true,0);
        }
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(cancellationToken);
        var articulosCreados=0;
        if(linePayload.Any(line=>string.Equals(Convert.ToString(line["clasificacion"]),"INVENTARIO",StringComparison.Ordinal)))
        {
            await using var articleCommand=connection.CreateCommand();
            articleCommand.Transaction=transaction;
            articleCommand.CommandType=CommandType.StoredProcedure;
            articleCommand.CommandText="comp.usp_AsegurarArticulosDocumentoXml";
            Add(articleCommand,"@EmpresaId",SqlDbType.BigInt,empresaId);
            Add(articleCommand,"@ProveedorIdentificacion",SqlDbType.NVarChar,input.ProveedorIdentificacion,30);
            Add(articleCommand,"@ProveedorRazonSocial",SqlDbType.NVarChar,input.ProveedorRazonSocial,200);
            Add(articleCommand,"@UsuarioId",SqlDbType.BigInt,input.UsuarioId);
            Add(articleCommand,"@CrearArticulosFaltantes",SqlDbType.Bit,input.CrearArticulosFaltantes);
            Add(articleCommand,"@LineasJson",SqlDbType.NVarChar,JsonSerializer.Serialize(linePayload),-1);
            await using var articleReader=await articleCommand.ExecuteReaderAsync(cancellationToken);
            while(await articleReader.ReadAsync(cancellationToken))
            {
                var numeroLinea=articleReader.GetInt32(0);
                var line=linePayload.First(x=>Convert.ToInt32(x["numeroLinea"])==numeroLinea);
                line["articuloId"]=articleReader.GetInt64(1);
                line["unidadMedidaId"]=articleReader.GetInt64(2);
                line["codigoExterno"]=articleReader.IsDBNull(3)?null:articleReader.GetString(3);
                if(articleReader.GetBoolean(5)) articulosCreados++;
            }
        }
        var lineasJson = JsonSerializer.Serialize(linePayload);
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandType = CommandType.StoredProcedure;
        command.CommandText = "comp.usp_CrearDocumentoProveedor";
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);
        Add(command,"@ProveedorIdentificacion",SqlDbType.NVarChar,input.ProveedorIdentificacion,30);
        Add(command,"@ProveedorRazonSocial",SqlDbType.NVarChar,input.ProveedorRazonSocial,200);
        Add(command,"@TipoDocumento",SqlDbType.VarChar,input.TipoDocumento,20);
        Add(command,"@NumeroDocumento",SqlDbType.NVarChar,input.NumeroDocumento,50);
        Add(command,"@FechaDocumento",SqlDbType.Date,input.FechaDocumento.ToDateTime(TimeOnly.MinValue));
        Add(command,"@FechaVencimiento",SqlDbType.Date,input.FechaVencimiento?.ToDateTime(TimeOnly.MinValue));
        Add(command,"@Moneda",SqlDbType.Char,input.Moneda,3);
        Add(command,"@CufeCude",SqlDbType.NVarChar,input.CufeCude,120);
        Add(command,"@HashXml",SqlDbType.Char,hashXml,64);
        Add(command,"@Fuente",SqlDbType.VarChar,input.Fuente,15);
        AddDecimal(command,"@SubtotalBruto",input.SubtotalBruto,20,4);
        AddDecimal(command,"@DescuentoTotal",input.DescuentoTotal,20,4);
        AddDecimal(command,"@ImpuestoTotal",input.ImpuestoTotal,20,4);
        AddDecimal(command,"@CargoTotal",input.CargoTotal,20,4);
        AddDecimal(command,"@TotalPagar",input.TotalPagar,20,4);
        Add(command,"@XmlOriginal",SqlDbType.NVarChar,input.XmlOriginal,-1);
        Add(command,"@UsuarioId",SqlDbType.BigInt,input.UsuarioId);
        Add(command,"@LineasJson",SqlDbType.NVarChar,lineasJson,-1);
        Add(command,"@DocumentoGuid",SqlDbType.UniqueIdentifier,input.DocumentoGuid);
        long documentoId;
        bool yaExistia;
        await using (var reader=await command.ExecuteReaderAsync(cancellationToken))
        {
            if(!await reader.ReadAsync(cancellationToken)) throw new InvalidOperationException("No se obtuvo el documento creado.");
            documentoId=reader.GetInt64(0);
            yaExistia=reader.GetBoolean(1);
        }
        if(!yaExistia)
        {
            await using var paymentCommand=connection.CreateCommand();
            paymentCommand.Transaction=transaction;
            paymentCommand.CommandText="""
                UPDATE comp.DocumentoProveedor
                SET CondicionPago=@CondicionPago,DiasCredito=@DiasCredito
                WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId;
                """;
            Add(paymentCommand,"@CondicionPago",SqlDbType.VarChar,input.CondicionPago.Trim().ToUpperInvariant(),10);
            Add(paymentCommand,"@DiasCredito",SqlDbType.Int,input.DiasCredito);
            Add(paymentCommand,"@EmpresaId",SqlDbType.BigInt,empresaId);
            Add(paymentCommand,"@DocumentoProveedorId",SqlDbType.BigInt,documentoId);
            await paymentCommand.ExecuteNonQueryAsync(cancellationToken);
        }
        if(serialPayload.Length>0&&!yaExistia)
        {
            await using var serialCommand=connection.CreateCommand();
            serialCommand.Transaction=transaction;
            serialCommand.CommandType=CommandType.StoredProcedure;
            serialCommand.CommandText="comp.usp_GuardarUnidadesSerializadasDocumento";
            Add(serialCommand,"@EmpresaId",SqlDbType.BigInt,empresaId);
            Add(serialCommand,"@DocumentoProveedorId",SqlDbType.BigInt,documentoId);
            Add(serialCommand,"@UnidadesJson",SqlDbType.NVarChar,JsonSerializer.Serialize(serialPayload),-1);
            await serialCommand.ExecuteNonQueryAsync(cancellationToken);
        }
        if(tracePayload.Length>0&&!yaExistia)
        {
            await using var traceCommand=connection.CreateCommand();
            traceCommand.Transaction=transaction;
            traceCommand.CommandType=CommandType.StoredProcedure;
            traceCommand.CommandText="comp.usp_GuardarTrazabilidadDocumento";
            Add(traceCommand,"@EmpresaId",SqlDbType.BigInt,empresaId);
            Add(traceCommand,"@DocumentoProveedorId",SqlDbType.BigInt,documentoId);
            Add(traceCommand,"@TrazabilidadJson",SqlDbType.NVarChar,JsonSerializer.Serialize(tracePayload),-1);
            await traceCommand.ExecuteNonQueryAsync(cancellationToken);
        }
        if(retentionPayload.Length>0&&!yaExistia)
        {
            await using var retentionCommand=connection.CreateCommand();
            retentionCommand.Transaction=transaction;
            retentionCommand.CommandType=CommandType.StoredProcedure;
            retentionCommand.CommandText="comp.usp_GuardarRetencionesDocumento";
            Add(retentionCommand,"@EmpresaId",SqlDbType.BigInt,empresaId);
            Add(retentionCommand,"@DocumentoProveedorId",SqlDbType.BigInt,documentoId);
            Add(retentionCommand,"@RetencionesJson",SqlDbType.NVarChar,JsonSerializer.Serialize(retentionPayload),-1);
            await retentionCommand.ExecuteNonQueryAsync(cancellationToken);
        }
        await transaction.CommitAsync(cancellationToken);
        return new(documentoId,yaExistia,articulosCreados);
    }

    public async Task<IReadOnlyList<SupplierDocumentListItemResponse>> GetDocumentsAsync(long empresaId,string? query,string? estado,CancellationToken cancellationToken)
    {
        var normalizedQuery=string.IsNullOrWhiteSpace(query)?null:query.Trim();
        var normalizedStatus=string.IsNullOrWhiteSpace(estado)?null:estado.Trim().ToUpperInvariant();
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT TOP(250) d.DocumentoProveedorId,d.Estado,d.TipoDocumento,d.NumeroDocumento,t.RazonSocial,t.NumeroIdentificacion,
                   d.FechaDocumento,d.FechaVencimiento,d.CondicionPago,d.Moneda,d.TotalPagar,
                   (SELECT COUNT(*) FROM comp.DocumentoProveedorLinea l WHERE l.EmpresaId=d.EmpresaId AND l.DocumentoProveedorId=d.DocumentoProveedorId),
                   (SELECT COUNT(*) FROM comp.DocumentoProveedorLineaUnidad u JOIN comp.DocumentoProveedorLinea l ON l.EmpresaId=u.EmpresaId AND l.DocumentoProveedorLineaId=u.DocumentoProveedorLineaId WHERE l.EmpresaId=d.EmpresaId AND l.DocumentoProveedorId=d.DocumentoProveedorId),
                   d.Fuente,d.CreadoEnUtc,r.RecepcionMercanciaId,r.Estado,b.Nombre
            FROM comp.DocumentoProveedor d
            JOIN ter.Tercero t ON t.EmpresaId=d.EmpresaId AND t.TerceroId=d.TerceroId
            LEFT JOIN inv.RecepcionMercancia r ON r.EmpresaId=d.EmpresaId AND r.DocumentoProveedorId=d.DocumentoProveedorId
            LEFT JOIN inv.Bodega b ON b.EmpresaId=r.EmpresaId AND b.BodegaId=r.BodegaId
            WHERE d.EmpresaId=@EmpresaId AND (@Estado IS NULL OR d.Estado=@Estado)
              AND (@Query IS NULL OR d.NumeroDocumento LIKE '%'+@Query+'%' OR t.RazonSocial LIKE '%'+@Query+'%' OR t.NumeroIdentificacion LIKE '%'+@Query+'%'
                   OR EXISTS(SELECT 1 FROM comp.DocumentoProveedorLineaUnidad u JOIN comp.DocumentoProveedorLinea l ON l.EmpresaId=u.EmpresaId AND l.DocumentoProveedorLineaId=u.DocumentoProveedorLineaId WHERE l.EmpresaId=d.EmpresaId AND l.DocumentoProveedorId=d.DocumentoProveedorId AND (u.Serial LIKE '%'+@Query+'%' OR u.Motor LIKE '%'+@Query+'%' OR u.Chasis LIKE '%'+@Query+'%' OR u.Vin LIKE '%'+@Query+'%')))
            ORDER BY d.CreadoEnUtc DESC,d.DocumentoProveedorId DESC;
            """;
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);
        Add(command,"@Query",SqlDbType.NVarChar,normalizedQuery,120);
        Add(command,"@Estado",SqlDbType.VarChar,normalizedStatus,15);
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);
        var result=new List<SupplierDocumentListItemResponse>();
        while(await reader.ReadAsync(cancellationToken)) result.Add(new(
            reader.GetInt64(0),reader.GetString(1),reader.GetString(2),reader.GetString(3),reader.GetString(4),reader.GetString(5),
            DateOnly.FromDateTime(reader.GetDateTime(6)),reader.IsDBNull(7)?null:DateOnly.FromDateTime(reader.GetDateTime(7)),reader.GetString(8),reader.GetString(9),reader.GetDecimal(10),
            reader.GetInt32(11),reader.GetInt32(12),reader.GetString(13),reader.GetDateTime(14),reader.IsDBNull(15)?null:reader.GetInt64(15),reader.IsDBNull(16)?null:reader.GetString(16),reader.IsDBNull(17)?null:reader.GetString(17)));
        return result;
    }

    public async Task<SupplierDocumentDetailResponse?> GetDocumentDetailAsync(long empresaId,long documentoId,CancellationToken cancellationToken)
    {
        var workflow=await GetWorkflowAsync(empresaId,documentoId,cancellationToken);
        if(workflow is null) return null;
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT l.DocumentoProveedorLineaId,l.NumeroLinea,l.ArticuloId,a.Codigo,l.CodigoExterno,l.Descripcion,l.Clasificacion,l.Cantidad,u.Codigo,
                   l.PrecioUnitario,l.SubtotalBruto,l.Descuento,l.Impuesto,l.Retencion,l.Cargo,l.TotalNeto
            FROM comp.DocumentoProveedorLinea l
            LEFT JOIN inv.Articulo a ON a.EmpresaId=l.EmpresaId AND a.ArticuloId=l.ArticuloId
            LEFT JOIN inv.UnidadMedida u ON u.EmpresaId=l.EmpresaId AND u.UnidadMedidaId=l.UnidadMedidaId
            WHERE l.EmpresaId=@EmpresaId AND l.DocumentoProveedorId=@DocumentoProveedorId
            ORDER BY l.NumeroLinea;
            SELECT u.DocumentoProveedorLineaId,u.NumeroUnidad,u.Serial,u.Motor,u.Chasis,u.Vin,u.Color,u.Modelo,u.InformacionOriginal
            FROM comp.DocumentoProveedorLineaUnidad u
            JOIN comp.DocumentoProveedorLinea l ON l.EmpresaId=u.EmpresaId AND l.DocumentoProveedorLineaId=u.DocumentoProveedorLineaId
            WHERE l.EmpresaId=@EmpresaId AND l.DocumentoProveedorId=@DocumentoProveedorId
            ORDER BY l.NumeroLinea,u.NumeroUnidad;
            """;
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);
        Add(command,"@DocumentoProveedorId",SqlDbType.BigInt,documentoId);
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);
        var lines=new List<SupplierDocumentLineDetailResponse>();
        var serialsByLine=new Dictionary<long,List<SupplierDocumentSerialDetailResponse>>();
        while(await reader.ReadAsync(cancellationToken))
        {
            var lineId=reader.GetInt64(0);var serials=new List<SupplierDocumentSerialDetailResponse>();serialsByLine[lineId]=serials;
            lines.Add(new(lineId,reader.GetInt32(1),reader.IsDBNull(2)?null:reader.GetInt64(2),reader.IsDBNull(3)?null:reader.GetString(3),reader.IsDBNull(4)?null:reader.GetString(4),reader.GetString(5),reader.GetString(6),reader.GetDecimal(7),reader.IsDBNull(8)?null:reader.GetString(8),reader.GetDecimal(9),reader.GetDecimal(10),reader.GetDecimal(11),reader.GetDecimal(12),reader.GetDecimal(13),reader.GetDecimal(14),reader.GetDecimal(15),serials));
        }
        if(await reader.NextResultAsync(cancellationToken)) while(await reader.ReadAsync(cancellationToken))
        {
            var lineId=reader.GetInt64(0);
            if(serialsByLine.TryGetValue(lineId,out var serials)) serials.Add(new(reader.GetInt32(1),reader.IsDBNull(2)?null:reader.GetString(2),reader.IsDBNull(3)?null:reader.GetString(3),reader.IsDBNull(4)?null:reader.GetString(4),reader.IsDBNull(5)?null:reader.GetString(5),reader.IsDBNull(6)?null:reader.GetString(6),reader.IsDBNull(7)?null:reader.GetString(7),reader.IsDBNull(8)?null:reader.GetString(8)));
        }
        return new(workflow,lines);
    }

    public async Task<RejectSupplierDocumentResponse> RejectDocumentAsync(long empresaId,long documentoId,long userId,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var transaction=(SqlTransaction)await connection.BeginTransactionAsync(cancellationToken);
        await using var command=connection.CreateCommand();command.Transaction=transaction;
        command.CommandText="""
            DECLARE @Estado varchar(15);
            SELECT @Estado=Estado FROM comp.DocumentoProveedor WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId;
            IF @Estado IS NULL THROW 51340,'El borrador no existe.',1;
            IF @Estado='RECHAZADO' BEGIN SELECT @DocumentoProveedorId,'RECHAZADO',CAST(1 AS bit); RETURN; END;
            IF @Estado<>'BORRADOR' OR EXISTS(SELECT 1 FROM inv.RecepcionMercancia WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId) OR EXISTS(SELECT 1 FROM comp.CausacionServicio WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId)
                THROW 51341,'Solo se puede anular un borrador que todavía no tenga procesos preparados.',1;
            UPDATE comp.DocumentoProveedor SET Estado='RECHAZADO' WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId;
            INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresPosteriores,AplicacionOrigen)
            SELECT @EmpresaId,@UsuarioId,'DOCUMENTO_PROVEEDOR_ANULADO','comp.DocumentoProveedor',CONVERT(nvarchar(100),DocumentoProveedorId),NumeroDocumento,N'{"estado":"RECHAZADO"}','COMPRAS'
            FROM comp.DocumentoProveedor WHERE EmpresaId=@EmpresaId AND DocumentoProveedorId=@DocumentoProveedorId;
            SELECT @DocumentoProveedorId,'RECHAZADO',CAST(0 AS bit);
            """;
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(command,"@DocumentoProveedorId",SqlDbType.BigInt,documentoId);Add(command,"@UsuarioId",SqlDbType.BigInt,userId);
        RejectSupplierDocumentResponse result;
        await using(var reader=await command.ExecuteReaderAsync(cancellationToken)){if(!await reader.ReadAsync(cancellationToken))throw new InvalidOperationException("No fue posible anular el borrador.");result=new(reader.GetInt64(0),reader.GetString(1),reader.GetBoolean(2));}
        await transaction.CommitAsync(cancellationToken);return result;
    }

    public async Task<SupplierDocumentWorkflowResponse?> GetWorkflowAsync(long empresaId,long documentoId,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT d.DocumentoProveedorId,d.Estado,d.TipoDocumento,d.NumeroDocumento,t.RazonSocial,t.NumeroIdentificacion,
                   d.FechaDocumento,d.FechaVencimiento,d.CondicionPago,d.DiasCredito,d.Moneda,d.CufeCude,d.HashXml,
                   CONVERT(bit,IIF(d.XmlOriginal IS NULL,0,1)),d.SubtotalBruto,d.DescuentoTotal,d.ImpuestoTotal,d.CargoTotal,d.TotalPagar,
                   (SELECT COUNT(*) FROM comp.DocumentoProveedorLinea l WHERE l.EmpresaId=d.EmpresaId AND l.DocumentoProveedorId=d.DocumentoProveedorId),
                   (SELECT COUNT(*) FROM comp.DocumentoProveedorLineaUnidad u JOIN comp.DocumentoProveedorLinea l ON l.EmpresaId=u.EmpresaId AND l.DocumentoProveedorLineaId=u.DocumentoProveedorLineaId WHERE l.EmpresaId=d.EmpresaId AND l.DocumentoProveedorId=d.DocumentoProveedorId),
                   r.RecepcionMercanciaId,r.Numero,r.Estado,c.CausacionServicioId,c.Numero,c.Estado
            FROM comp.DocumentoProveedor d
            JOIN ter.Tercero t ON t.EmpresaId=d.EmpresaId AND t.TerceroId=d.TerceroId
            LEFT JOIN inv.RecepcionMercancia r ON r.EmpresaId=d.EmpresaId AND r.DocumentoProveedorId=d.DocumentoProveedorId
            LEFT JOIN comp.CausacionServicio c ON c.EmpresaId=d.EmpresaId AND c.DocumentoProveedorId=d.DocumentoProveedorId
            WHERE d.EmpresaId=@EmpresaId AND d.DocumentoProveedorId=@DocumentoProveedorId;
            """;
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);
        Add(command,"@DocumentoProveedorId",SqlDbType.BigInt,documentoId);
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);
        if(!await reader.ReadAsync(cancellationToken)) return null;
        return new(
            reader.GetInt64(0),reader.GetString(1),reader.GetString(2),reader.GetString(3),reader.GetString(4),reader.GetString(5),
            DateOnly.FromDateTime(reader.GetDateTime(6)),reader.IsDBNull(7)?null:DateOnly.FromDateTime(reader.GetDateTime(7)),reader.GetString(8),reader.GetInt32(9),reader.GetString(10),
            reader.IsDBNull(11)?null:reader.GetString(11),reader.IsDBNull(12)?null:reader.GetString(12),reader.GetBoolean(13),
            reader.GetDecimal(14),reader.GetDecimal(15),reader.GetDecimal(16),reader.GetDecimal(17),reader.GetDecimal(18),reader.GetInt32(19),reader.GetInt32(20),
            reader.IsDBNull(21)?null:reader.GetInt64(21),reader.IsDBNull(22)?null:reader.GetString(22),reader.IsDBNull(23)?null:reader.GetString(23),
            reader.IsDBNull(24)?null:reader.GetInt64(24),reader.IsDBNull(25)?null:reader.GetString(25),reader.IsDBNull(26)?null:reader.GetString(26));
    }

    public async Task<IReadOnlyList<ReceiptMovementResponse>> GetReceiptMovementsAsync(long empresaId,long recepcionId,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT m.MovimientoInventarioId,l.NumeroLinea,a.Codigo,a.Descripcion,m.CantidadEntrada,
                   m.CostoUnitarioMovimiento,m.ValorMovimiento,m.ExistenciaPosterior,m.CostoPromedioPosterior,b.Nombre,x.NumeroLote,x.FechaVencimiento,m.FechaContable
            FROM inv.MovimientoInventario m
            JOIN inv.RecepcionMercanciaLinea l ON l.EmpresaId=m.EmpresaId AND l.RecepcionMercanciaLineaId=m.DocumentoLineaOrigenId
            JOIN inv.Articulo a ON a.EmpresaId=m.EmpresaId AND a.ArticuloId=m.ArticuloId
            JOIN inv.Bodega b ON b.EmpresaId=m.EmpresaId AND b.BodegaId=m.BodegaId
            LEFT JOIN inv.Lote x ON x.EmpresaId=m.EmpresaId AND x.LoteId=m.LoteId
            WHERE m.EmpresaId=@EmpresaId AND m.TipoDocumentoOrigen='RECEPCION_MERCANCIA' AND m.DocumentoOrigenId=@RecepcionMercanciaId
            ORDER BY l.NumeroLinea,m.MovimientoInventarioId;
            """;
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);
        Add(command,"@RecepcionMercanciaId",SqlDbType.BigInt,recepcionId);
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);
        var result=new List<ReceiptMovementResponse>();
        while(await reader.ReadAsync(cancellationToken)) result.Add(new(reader.GetInt64(0),reader.GetInt32(1),reader.GetString(2),reader.GetString(3),reader.GetDecimal(4),reader.GetDecimal(5),reader.GetDecimal(6),reader.GetDecimal(7),reader.GetDecimal(8),reader.GetString(9),reader.IsDBNull(10)?null:reader.GetString(10),reader.IsDBNull(11)?null:DateOnly.FromDateTime(reader.GetDateTime(11)),DateOnly.FromDateTime(reader.GetDateTime(12))));
        return result;
    }

    public async Task<IReadOnlyList<WarehouseReceiptListItemResponse>> GetWarehouseReceiptsAsync(long empresaId,long? bodegaId,string? query,CancellationToken cancellationToken)
    {
        var normalizedQuery=string.IsNullOrWhiteSpace(query)?null:query.Trim();
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT TOP(200) r.RecepcionMercanciaId,r.Numero,r.Estado,d.DocumentoProveedorId,d.TipoDocumento,d.NumeroDocumento,
                   t.RazonSocial,d.FechaDocumento,r.FechaContable,b.Nombre,
                   COUNT(DISTINCT l.RecepcionMercanciaLineaId) Lineas,
                   COUNT(u.RecepcionMercanciaUnidadId) Unidades,
                   COUNT(rv.RecepcionMercanciaRevisionUnidadId) Revisadas,
                   SUM(CASE WHEN rv.EstadoFisico='RECIBIDA_CONFORME' THEN 1 ELSE 0 END) Conforme,
                   SUM(CASE WHEN rv.EstadoFisico='RECIBIDA_NOVEDAD' THEN 1 ELSE 0 END) Novedad,
                   SUM(CASE WHEN rv.EstadoFisico='NO_RECIBIDA' THEN 1 ELSE 0 END) NoRecibida
            FROM inv.RecepcionMercancia r
            JOIN comp.DocumentoProveedor d ON d.EmpresaId=r.EmpresaId AND d.DocumentoProveedorId=r.DocumentoProveedorId
            JOIN ter.Tercero t ON t.EmpresaId=r.EmpresaId AND t.TerceroId=r.TerceroId
            JOIN inv.Bodega b ON b.EmpresaId=r.EmpresaId AND b.BodegaId=r.BodegaId
            JOIN inv.RecepcionMercanciaLinea l ON l.EmpresaId=r.EmpresaId AND l.RecepcionMercanciaId=r.RecepcionMercanciaId
            LEFT JOIN inv.RecepcionMercanciaUnidad u ON u.EmpresaId=l.EmpresaId AND u.RecepcionMercanciaLineaId=l.RecepcionMercanciaLineaId
            LEFT JOIN inv.RecepcionMercanciaRevisionUnidad rv ON rv.EmpresaId=u.EmpresaId AND rv.RecepcionMercanciaUnidadId=u.RecepcionMercanciaUnidadId
            WHERE r.EmpresaId=@EmpresaId AND r.Estado<>'CONTABILIZADA' AND (@BodegaId IS NULL OR r.BodegaId=@BodegaId)
              AND (@Query IS NULL OR r.Numero LIKE '%'+@Query+'%' OR d.NumeroDocumento LIKE '%'+@Query+'%' OR t.RazonSocial LIKE '%'+@Query+'%'
                   OR EXISTS(SELECT 1 FROM inv.RecepcionMercanciaUnidad xu JOIN inv.RecepcionMercanciaLinea xl ON xl.EmpresaId=xu.EmpresaId AND xl.RecepcionMercanciaLineaId=xu.RecepcionMercanciaLineaId WHERE xl.EmpresaId=r.EmpresaId AND xl.RecepcionMercanciaId=r.RecepcionMercanciaId AND (xu.Serial LIKE '%'+@Query+'%' OR xu.Motor LIKE '%'+@Query+'%' OR xu.Chasis LIKE '%'+@Query+'%' OR xu.Vin LIKE '%'+@Query+'%')))
            GROUP BY r.RecepcionMercanciaId,r.Numero,r.Estado,d.DocumentoProveedorId,d.TipoDocumento,d.NumeroDocumento,t.RazonSocial,d.FechaDocumento,r.FechaContable,b.Nombre
            ORDER BY r.FechaContable DESC,r.RecepcionMercanciaId DESC;
            """;
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);
        Add(command,"@BodegaId",SqlDbType.BigInt,bodegaId);
        Add(command,"@Query",SqlDbType.NVarChar,normalizedQuery,120);
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);
        var result=new List<WarehouseReceiptListItemResponse>();
        while(await reader.ReadAsync(cancellationToken))
            result.Add(new(reader.GetInt64(0),reader.GetString(1),reader.GetString(2),reader.GetInt64(3),reader.GetString(4),reader.GetString(5),reader.GetString(6),
                DateOnly.FromDateTime(reader.GetDateTime(7)),DateOnly.FromDateTime(reader.GetDateTime(8)),reader.GetString(9),reader.GetInt32(10),reader.GetInt32(11),
                reader.GetInt32(12),reader.GetInt32(13),reader.GetInt32(14),reader.GetInt32(15)));
        return result;
    }

    public async Task<IReadOnlyList<WarehouseReceiptListItemResponse>> GetWarehouseReceiptHistoryAsync(long empresaId,long? bodegaId,string? query,DateOnly? desde,DateOnly? hasta,CancellationToken cancellationToken)
    {
        var normalizedQuery=string.IsNullOrWhiteSpace(query)?null:query.Trim();
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT TOP(500) r.RecepcionMercanciaId,r.Numero,r.Estado,d.DocumentoProveedorId,d.TipoDocumento,d.NumeroDocumento,
                   t.RazonSocial,d.FechaDocumento,r.FechaContable,b.Nombre,
                   COUNT(DISTINCT l.RecepcionMercanciaLineaId) Lineas,
                   COUNT(u.RecepcionMercanciaUnidadId) Unidades,
                   COUNT(rv.RecepcionMercanciaRevisionUnidadId) Revisadas,
                   SUM(CASE WHEN rv.EstadoFisico='RECIBIDA_CONFORME' THEN 1 ELSE 0 END) Conforme,
                   SUM(CASE WHEN rv.EstadoFisico='RECIBIDA_NOVEDAD' THEN 1 ELSE 0 END) Novedad,
                   SUM(CASE WHEN rv.EstadoFisico='NO_RECIBIDA' THEN 1 ELSE 0 END) NoRecibida
            FROM inv.RecepcionMercancia r
            JOIN comp.DocumentoProveedor d ON d.EmpresaId=r.EmpresaId AND d.DocumentoProveedorId=r.DocumentoProveedorId
            JOIN ter.Tercero t ON t.EmpresaId=r.EmpresaId AND t.TerceroId=r.TerceroId
            JOIN inv.Bodega b ON b.EmpresaId=r.EmpresaId AND b.BodegaId=r.BodegaId
            JOIN inv.RecepcionMercanciaLinea l ON l.EmpresaId=r.EmpresaId AND l.RecepcionMercanciaId=r.RecepcionMercanciaId
            LEFT JOIN inv.RecepcionMercanciaUnidad u ON u.EmpresaId=l.EmpresaId AND u.RecepcionMercanciaLineaId=l.RecepcionMercanciaLineaId
            LEFT JOIN inv.RecepcionMercanciaRevisionUnidad rv ON rv.EmpresaId=u.EmpresaId AND rv.RecepcionMercanciaUnidadId=u.RecepcionMercanciaUnidadId
            WHERE r.EmpresaId=@EmpresaId AND (@BodegaId IS NULL OR r.BodegaId=@BodegaId)
              AND (@Desde IS NULL OR r.FechaContable>=@Desde) AND (@Hasta IS NULL OR r.FechaContable<=@Hasta)
              AND (@Query IS NULL OR r.Numero LIKE '%'+@Query+'%' OR d.NumeroDocumento LIKE '%'+@Query+'%' OR t.RazonSocial LIKE '%'+@Query+'%'
                   OR EXISTS(SELECT 1 FROM inv.RecepcionMercanciaUnidad xu JOIN inv.RecepcionMercanciaLinea xl ON xl.EmpresaId=xu.EmpresaId AND xl.RecepcionMercanciaLineaId=xu.RecepcionMercanciaLineaId WHERE xl.EmpresaId=r.EmpresaId AND xl.RecepcionMercanciaId=r.RecepcionMercanciaId AND (xu.Serial LIKE '%'+@Query+'%' OR xu.Motor LIKE '%'+@Query+'%' OR xu.Chasis LIKE '%'+@Query+'%' OR xu.Vin LIKE '%'+@Query+'%')))
            GROUP BY r.RecepcionMercanciaId,r.Numero,r.Estado,d.DocumentoProveedorId,d.TipoDocumento,d.NumeroDocumento,t.RazonSocial,d.FechaDocumento,r.FechaContable,b.Nombre
            ORDER BY r.FechaContable DESC,r.RecepcionMercanciaId DESC;
            """;
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);
        Add(command,"@BodegaId",SqlDbType.BigInt,bodegaId);
        Add(command,"@Query",SqlDbType.NVarChar,normalizedQuery,120);
        Add(command,"@Desde",SqlDbType.Date,desde?.ToDateTime(TimeOnly.MinValue));
        Add(command,"@Hasta",SqlDbType.Date,hasta?.ToDateTime(TimeOnly.MinValue));
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);
        var result=new List<WarehouseReceiptListItemResponse>();
        while(await reader.ReadAsync(cancellationToken))
            result.Add(new(reader.GetInt64(0),reader.GetString(1),reader.GetString(2),reader.GetInt64(3),reader.GetString(4),reader.GetString(5),reader.GetString(6),
                DateOnly.FromDateTime(reader.GetDateTime(7)),DateOnly.FromDateTime(reader.GetDateTime(8)),reader.GetString(9),reader.GetInt32(10),reader.GetInt32(11),
                reader.GetInt32(12),reader.GetInt32(13),reader.GetInt32(14),reader.GetInt32(15)));
        return result;
    }

    public async Task<WarehouseReceiptDetailResponse?> GetWarehouseReceiptDetailAsync(long empresaId,long recepcionId,CancellationToken cancellationToken,bool includePosted=false)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        WarehouseReceiptListItemResponse? header;
        await using(var headerCommand=connection.CreateCommand())
        {
            headerCommand.CommandText="""
                SELECT r.RecepcionMercanciaId,r.Numero,r.Estado,d.DocumentoProveedorId,d.TipoDocumento,d.NumeroDocumento,
                       t.RazonSocial,d.FechaDocumento,r.FechaContable,b.Nombre,
                       COUNT(DISTINCT l.RecepcionMercanciaLineaId) Lineas,
                       COUNT(u.RecepcionMercanciaUnidadId) Unidades,
                       COUNT(rv.RecepcionMercanciaRevisionUnidadId) Revisadas,
                       SUM(CASE WHEN rv.EstadoFisico='RECIBIDA_CONFORME' THEN 1 ELSE 0 END) Conforme,
                       SUM(CASE WHEN rv.EstadoFisico='RECIBIDA_NOVEDAD' THEN 1 ELSE 0 END) Novedad,
                       SUM(CASE WHEN rv.EstadoFisico='NO_RECIBIDA' THEN 1 ELSE 0 END) NoRecibida
                FROM inv.RecepcionMercancia r
                JOIN comp.DocumentoProveedor d ON d.EmpresaId=r.EmpresaId AND d.DocumentoProveedorId=r.DocumentoProveedorId
                JOIN ter.Tercero t ON t.EmpresaId=r.EmpresaId AND t.TerceroId=r.TerceroId
                JOIN inv.Bodega b ON b.EmpresaId=r.EmpresaId AND b.BodegaId=r.BodegaId
                JOIN inv.RecepcionMercanciaLinea l ON l.EmpresaId=r.EmpresaId AND l.RecepcionMercanciaId=r.RecepcionMercanciaId
                LEFT JOIN inv.RecepcionMercanciaUnidad u ON u.EmpresaId=l.EmpresaId AND u.RecepcionMercanciaLineaId=l.RecepcionMercanciaLineaId
                LEFT JOIN inv.RecepcionMercanciaRevisionUnidad rv ON rv.EmpresaId=u.EmpresaId AND rv.RecepcionMercanciaUnidadId=u.RecepcionMercanciaUnidadId
                WHERE r.EmpresaId=@EmpresaId AND r.RecepcionMercanciaId=@RecepcionMercanciaId AND (@IncludePosted=1 OR r.Estado<>'CONTABILIZADA')
                GROUP BY r.RecepcionMercanciaId,r.Numero,r.Estado,d.DocumentoProveedorId,d.TipoDocumento,d.NumeroDocumento,t.RazonSocial,d.FechaDocumento,r.FechaContable,b.Nombre;
                """;
            Add(headerCommand,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(headerCommand,"@RecepcionMercanciaId",SqlDbType.BigInt,recepcionId);
            Add(headerCommand,"@IncludePosted",SqlDbType.Bit,includePosted);
            await using var headerReader=await headerCommand.ExecuteReaderAsync(cancellationToken);
            header=await headerReader.ReadAsync(cancellationToken)
                ? new(headerReader.GetInt64(0),headerReader.GetString(1),headerReader.GetString(2),headerReader.GetInt64(3),headerReader.GetString(4),headerReader.GetString(5),headerReader.GetString(6),
                    DateOnly.FromDateTime(headerReader.GetDateTime(7)),DateOnly.FromDateTime(headerReader.GetDateTime(8)),headerReader.GetString(9),headerReader.GetInt32(10),headerReader.GetInt32(11),
                    headerReader.GetInt32(12),headerReader.GetInt32(13),headerReader.GetInt32(14),headerReader.GetInt32(15))
                : null;
        }
        if(header is null) return null;
        await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT u.RecepcionMercanciaUnidadId,l.NumeroLinea,a.Codigo,a.Descripcion,u.NumeroUnidad,
                   u.Serial,u.Motor,u.Chasis,u.Vin,u.Color,u.Modelo,
                   rv.EstadoFisico,rv.Observacion,s.NombreCompleto,rv.RevisadoEnUtc
            FROM inv.RecepcionMercanciaUnidad u
            JOIN inv.RecepcionMercanciaLinea l ON l.EmpresaId=u.EmpresaId AND l.RecepcionMercanciaLineaId=u.RecepcionMercanciaLineaId
            JOIN inv.Articulo a ON a.EmpresaId=l.EmpresaId AND a.ArticuloId=l.ArticuloId
            LEFT JOIN inv.RecepcionMercanciaRevisionUnidad rv ON rv.EmpresaId=u.EmpresaId AND rv.RecepcionMercanciaUnidadId=u.RecepcionMercanciaUnidadId
            LEFT JOIN seg.Usuario s ON s.UsuarioId=rv.RevisadoPorUsuarioId
            WHERE l.EmpresaId=@EmpresaId AND l.RecepcionMercanciaId=@RecepcionMercanciaId
            ORDER BY l.NumeroLinea,u.NumeroUnidad;
            """;
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(command,"@RecepcionMercanciaId",SqlDbType.BigInt,recepcionId);
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);
        var units=new List<WarehouseReceiptUnitResponse>();
        while(await reader.ReadAsync(cancellationToken))
            units.Add(new(reader.GetInt64(0),reader.GetInt32(1),reader.GetString(2),reader.GetString(3),reader.GetInt32(4),
                reader.IsDBNull(5)?null:reader.GetString(5),reader.IsDBNull(6)?null:reader.GetString(6),reader.IsDBNull(7)?null:reader.GetString(7),
                reader.IsDBNull(8)?null:reader.GetString(8),reader.IsDBNull(9)?null:reader.GetString(9),reader.IsDBNull(10)?null:reader.GetString(10),
                reader.IsDBNull(11)?null:reader.GetString(11),reader.IsDBNull(12)?null:reader.GetString(12),reader.IsDBNull(13)?null:reader.GetString(13),
                reader.IsDBNull(14)?null:reader.GetDateTime(14)));
        return header is null ? null : new(header,units);
    }

    public async Task<IReadOnlyList<WarehouseReceiptIssueResponse>> GetPendingWarehouseReceiptIssuesAsync(long empresaId,long? bodegaId,string? query,string? tipo,DateOnly? desde,DateOnly? hasta,CancellationToken cancellationToken)
    {
        var normalizedQuery=string.IsNullOrWhiteSpace(query)?null:query.Trim();
        var normalizedType=string.IsNullOrWhiteSpace(tipo)?null:tipo.Trim().ToUpperInvariant();
        if(normalizedType is not null and not ("RECIBIDA_NOVEDAD" or "NO_RECIBIDA"))
            throw new ArgumentException("El tipo de novedad no es válido.",nameof(tipo));
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT TOP(500)
                   rv.RecepcionMercanciaRevisionUnidadId,r.RecepcionMercanciaId,r.Numero,d.DocumentoProveedorId,
                   d.TipoDocumento,d.NumeroDocumento,t.RazonSocial,d.FechaDocumento,r.FechaContable,b.Nombre,
                   u.RecepcionMercanciaUnidadId,l.NumeroLinea,a.Codigo,a.Descripcion,u.NumeroUnidad,
                   u.Serial,u.Motor,u.Chasis,u.Vin,u.Color,u.Modelo,
                   rv.EstadoFisico,rv.Observacion,s.NombreCompleto,rv.RevisadoEnUtc
            FROM inv.RecepcionMercanciaRevisionUnidad rv
            JOIN inv.RecepcionMercanciaUnidad u ON u.EmpresaId=rv.EmpresaId AND u.RecepcionMercanciaUnidadId=rv.RecepcionMercanciaUnidadId
            JOIN inv.RecepcionMercanciaLinea l ON l.EmpresaId=u.EmpresaId AND l.RecepcionMercanciaLineaId=u.RecepcionMercanciaLineaId
            JOIN inv.RecepcionMercancia r ON r.EmpresaId=l.EmpresaId AND r.RecepcionMercanciaId=l.RecepcionMercanciaId
            JOIN comp.DocumentoProveedor d ON d.EmpresaId=r.EmpresaId AND d.DocumentoProveedorId=r.DocumentoProveedorId
            JOIN ter.Tercero t ON t.EmpresaId=r.EmpresaId AND t.TerceroId=r.TerceroId
            JOIN inv.Bodega b ON b.EmpresaId=r.EmpresaId AND b.BodegaId=r.BodegaId
            JOIN inv.Articulo a ON a.EmpresaId=l.EmpresaId AND a.ArticuloId=l.ArticuloId
            JOIN seg.Usuario s ON s.UsuarioId=rv.RevisadoPorUsuarioId
            WHERE rv.EmpresaId=@EmpresaId
              AND rv.EstadoFisico IN('RECIBIDA_NOVEDAD','NO_RECIBIDA')
              AND rv.GestionadaEnUtc IS NULL
              AND (@BodegaId IS NULL OR r.BodegaId=@BodegaId)
              AND (@Tipo IS NULL OR rv.EstadoFisico=@Tipo)
              AND (@Desde IS NULL OR r.FechaContable>=@Desde)
              AND (@Hasta IS NULL OR r.FechaContable<=@Hasta)
              AND (@Query IS NULL OR d.NumeroDocumento LIKE '%'+@Query+'%' OR r.Numero LIKE '%'+@Query+'%'
                   OR t.RazonSocial LIKE '%'+@Query+'%' OR a.Codigo LIKE '%'+@Query+'%' OR a.Descripcion LIKE '%'+@Query+'%'
                   OR u.Serial LIKE '%'+@Query+'%' OR u.Motor LIKE '%'+@Query+'%' OR u.Chasis LIKE '%'+@Query+'%' OR u.Vin LIKE '%'+@Query+'%'
                   OR rv.Observacion LIKE '%'+@Query+'%')
            ORDER BY d.FechaDocumento DESC,d.DocumentoProveedorId DESC,l.NumeroLinea,u.NumeroUnidad;
            """;
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);
        Add(command,"@BodegaId",SqlDbType.BigInt,bodegaId);
        Add(command,"@Query",SqlDbType.NVarChar,normalizedQuery,120);
        Add(command,"@Tipo",SqlDbType.VarChar,normalizedType,20);
        Add(command,"@Desde",SqlDbType.Date,desde?.ToDateTime(TimeOnly.MinValue));
        Add(command,"@Hasta",SqlDbType.Date,hasta?.ToDateTime(TimeOnly.MinValue));
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);
        var result=new List<WarehouseReceiptIssueResponse>();
        while(await reader.ReadAsync(cancellationToken))
            result.Add(new(reader.GetInt64(0),reader.GetInt64(1),reader.GetString(2),reader.GetInt64(3),reader.GetString(4),reader.GetString(5),reader.GetString(6),
                DateOnly.FromDateTime(reader.GetDateTime(7)),DateOnly.FromDateTime(reader.GetDateTime(8)),reader.GetString(9),reader.GetInt64(10),reader.GetInt32(11),reader.GetString(12),reader.GetString(13),reader.GetInt32(14),
                reader.IsDBNull(15)?null:reader.GetString(15),reader.IsDBNull(16)?null:reader.GetString(16),reader.IsDBNull(17)?null:reader.GetString(17),reader.IsDBNull(18)?null:reader.GetString(18),
                reader.IsDBNull(19)?null:reader.GetString(19),reader.IsDBNull(20)?null:reader.GetString(20),reader.GetString(21),reader.IsDBNull(22)?null:reader.GetString(22),reader.GetString(23),reader.GetDateTime(24)));
        return result;
    }

    public async Task<ResolvedWarehouseReceiptIssueResponse> ResolveWarehouseReceiptIssueAsync(long empresaId,long revisionId,ResolveWarehouseReceiptIssueRequest input,CancellationToken cancellationToken)
    {
        var result=input.Resultado.Trim().ToUpperInvariant();
        if(result is not ("RECLAMO_PROVEEDOR" or "AJUSTE_INVENTARIO" or "DEVOLUCION" or "ACEPTADA_DOCUMENTADA" or "OTRA"))
            throw new ArgumentException("El resultado de gestión no es válido.",nameof(input));
        var note=string.IsNullOrWhiteSpace(input.ObservacionGestion)?null:input.ObservacionGestion.Trim();
        if(note?.Length>1000) throw new ArgumentException("La nota de gestión admite máximo 1000 caracteres.",nameof(input));
        if(result=="OTRA"&&note is null) throw new ArgumentException("Describe la gestión realizada cuando seleccionas Otra.",nameof(input));
        var userId=input.UsuarioId ?? throw new ArgumentException("No se identificó al administrador.",nameof(input));
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var transaction=(SqlTransaction)await connection.BeginTransactionAsync(cancellationToken);
        DateTime managedAt;
        await using(var command=connection.CreateCommand())
        {
            command.Transaction=transaction;
            command.CommandText="""
                UPDATE inv.RecepcionMercanciaRevisionUnidad WITH(UPDLOCK)
                SET ResultadoGestion=@Resultado,ObservacionGestion=@ObservacionGestion,
                    GestionadaPorUsuarioId=@UsuarioId,GestionadaEnUtc=SYSUTCDATETIME()
                OUTPUT inserted.GestionadaEnUtc
                WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaRevisionUnidadId=@RevisionId
                  AND EstadoFisico IN('RECIBIDA_NOVEDAD','NO_RECIBIDA') AND GestionadaEnUtc IS NULL;
                """;
            Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(command,"@RevisionId",SqlDbType.BigInt,revisionId);
            Add(command,"@Resultado",SqlDbType.VarChar,result,30);Add(command,"@ObservacionGestion",SqlDbType.NVarChar,note,1000);Add(command,"@UsuarioId",SqlDbType.BigInt,userId);
            var value=await command.ExecuteScalarAsync(cancellationToken);
            if(value is null) throw new InvalidOperationException("La novedad ya fue gestionada, dejó de estar pendiente o no existe.");
            managedAt=Convert.ToDateTime(value);
        }
        string managedBy;
        await using(var user=connection.CreateCommand())
        {
            user.Transaction=transaction;user.CommandText="SELECT NombreCompleto FROM seg.Usuario WHERE UsuarioId=@UsuarioId;";Add(user,"@UsuarioId",SqlDbType.BigInt,userId);
            managedBy=Convert.ToString(await user.ExecuteScalarAsync(cancellationToken)) ?? "Administrador";
        }
        await using(var audit=connection.CreateCommand())
        {
            audit.Transaction=transaction;
            audit.CommandText="INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@EmpresaId,@UsuarioId,'NOVEDAD_RECEPCION_GESTIONADA','inv.RecepcionMercanciaRevisionUnidad',CONVERT(nvarchar(100),@RevisionId),@Valores,'ADMINISTRACION');";
            Add(audit,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(audit,"@UsuarioId",SqlDbType.BigInt,userId);Add(audit,"@RevisionId",SqlDbType.BigInt,revisionId);
            Add(audit,"@Valores",SqlDbType.NVarChar,JsonSerializer.Serialize(new { resultado=result,observacionGestion=note }),-1);
            await audit.ExecuteNonQueryAsync(cancellationToken);
        }
        await transaction.CommitAsync(cancellationToken);
        return new(revisionId,"GESTIONADA",result,note,managedBy,managedAt);
    }

    public async Task<WarehouseReceiptCheckSummaryResponse> SaveWarehouseReceiptChecksAsync(long empresaId,long recepcionId,SaveWarehouseReceiptChecksRequest input,CancellationToken cancellationToken)
    {
        if(input.Revisiones.Count==0) throw new ArgumentException("Envía al menos una revisión física.",nameof(input));
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var transaction=(SqlTransaction)await connection.BeginTransactionAsync(cancellationToken);
        await using(var receipt=connection.CreateCommand())
        {
            receipt.Transaction=transaction;
            receipt.CommandText="SELECT Estado FROM inv.RecepcionMercancia WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionMercanciaId;";
            Add(receipt,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(receipt,"@RecepcionMercanciaId",SqlDbType.BigInt,recepcionId);
            var state=Convert.ToString(await receipt.ExecuteScalarAsync(cancellationToken));
            if(string.IsNullOrWhiteSpace(state)) throw new InvalidOperationException("La recepción no existe.");
            if(state=="CONTABILIZADA") throw new InvalidOperationException("La recepción ya fue contabilizada. La revisión física quedó cerrada.");
        }
        foreach(var review in input.Revisiones)
        {
            var status=review.EstadoFisico.Trim().ToUpperInvariant();
            if(status is not ("RECIBIDA_CONFORME" or "RECIBIDA_NOVEDAD" or "NO_RECIBIDA"))
                throw new ArgumentException("Estado físico no válido.",nameof(input));
            await using var command=connection.CreateCommand();
            command.Transaction=transaction;
            command.CommandText="""
                IF NOT EXISTS
                (
                    SELECT 1
                    FROM inv.RecepcionMercanciaUnidad u
                    JOIN inv.RecepcionMercanciaLinea l ON l.EmpresaId=u.EmpresaId AND l.RecepcionMercanciaLineaId=u.RecepcionMercanciaLineaId
                    WHERE u.EmpresaId=@EmpresaId AND u.RecepcionMercanciaUnidadId=@UnidadId AND l.RecepcionMercanciaId=@RecepcionMercanciaId
                ) THROW 51580,'La unidad no pertenece a esta recepción.',1;

                MERGE inv.RecepcionMercanciaRevisionUnidad AS target
                USING(SELECT @EmpresaId EmpresaId,@UnidadId RecepcionMercanciaUnidadId) AS source
                ON target.EmpresaId=source.EmpresaId AND target.RecepcionMercanciaUnidadId=source.RecepcionMercanciaUnidadId
                WHEN MATCHED THEN UPDATE SET EstadoFisico=@EstadoFisico,Observacion=@Observacion,RevisadoPorUsuarioId=@UsuarioId,ActualizadoEnUtc=SYSUTCDATETIME(),
                    ResultadoGestion=NULL,ObservacionGestion=NULL,GestionadaPorUsuarioId=NULL,GestionadaEnUtc=NULL
                WHEN NOT MATCHED THEN INSERT(EmpresaId,RecepcionMercanciaUnidadId,EstadoFisico,Observacion,RevisadoPorUsuarioId)
                    VALUES(@EmpresaId,@UnidadId,@EstadoFisico,@Observacion,@UsuarioId);
                """;
            Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);
            Add(command,"@RecepcionMercanciaId",SqlDbType.BigInt,recepcionId);
            Add(command,"@UnidadId",SqlDbType.BigInt,review.RecepcionMercanciaUnidadId);
            Add(command,"@EstadoFisico",SqlDbType.VarChar,status,20);
            Add(command,"@Observacion",SqlDbType.NVarChar,string.IsNullOrWhiteSpace(review.Observacion)?null:review.Observacion.Trim(),500);
            Add(command,"@UsuarioId",SqlDbType.BigInt,input.UsuarioId);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
        await using(var audit=connection.CreateCommand())
        {
            audit.Transaction=transaction;
            audit.CommandText="INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@EmpresaId,@UsuarioId,'RECEPCION_FISICA_REVISADA','inv.RecepcionMercancia',CONVERT(nvarchar(100),@RecepcionMercanciaId),@Valores,'BODEGA');";
            Add(audit,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(audit,"@UsuarioId",SqlDbType.BigInt,input.UsuarioId);Add(audit,"@RecepcionMercanciaId",SqlDbType.BigInt,recepcionId);
            Add(audit,"@Valores",SqlDbType.NVarChar,JsonSerializer.Serialize(new { revisiones=input.Revisiones.Count }),-1);
            await audit.ExecuteNonQueryAsync(cancellationToken);
        }
        await transaction.CommitAsync(cancellationToken);
        var detail=await GetWarehouseReceiptDetailAsync(empresaId,recepcionId,cancellationToken) ?? throw new InvalidOperationException("No fue posible leer la recepción revisada.");
        return new(recepcionId,detail.Recepcion.Revisadas,detail.Recepcion.RecibidasConforme,detail.Recepcion.RecibidasConNovedad,detail.Recepcion.NoRecibidas);
    }

    public async Task<PreparedSupplierDocumentResponse> PrepareAsync(long empresaId,long documentoId,PrepareSupplierDocumentRequest input,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandType=CommandType.StoredProcedure;
        command.CommandText="comp.usp_PrepararProcesosDocumento";
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);
        Add(command,"@DocumentoProveedorId",SqlDbType.BigInt,documentoId);
        Add(command,"@BodegaId",SqlDbType.BigInt,input.BodegaId);
        Add(command,"@PeriodoInventarioId",SqlDbType.BigInt,input.PeriodoInventarioId);
        Add(command,"@FechaContable",SqlDbType.Date,input.FechaContable.ToDateTime(TimeOnly.MinValue));
        Add(command,"@NumeroRecepcion",SqlDbType.NVarChar,input.NumeroRecepcion,50);
        Add(command,"@NumeroCausacion",SqlDbType.NVarChar,input.NumeroCausacion,50);
        Add(command,"@UsuarioId",SqlDbType.BigInt,input.UsuarioId);
        PreparedSupplierDocumentResponse result;
        await using(var reader=await command.ExecuteReaderAsync(cancellationToken))
        {
            if(!await reader.ReadAsync(cancellationToken)) throw new InvalidOperationException("No se obtuvo el resultado de preparación.");
            result=new(reader.GetInt64(0),reader.IsDBNull(1)?null:reader.GetInt64(1),reader.IsDBNull(2)?null:reader.GetInt64(2),reader.GetInt32(3),reader.GetInt32(4));
        }
        if(result.RecepcionMercanciaId is not null)
        {
            await using var traceCommand=connection.CreateCommand();
            traceCommand.CommandType=CommandType.StoredProcedure;
            traceCommand.CommandText="inv.usp_AplicarLotesRecepcionDocumento";
            Add(traceCommand,"@EmpresaId",SqlDbType.BigInt,empresaId);
            Add(traceCommand,"@DocumentoProveedorId",SqlDbType.BigInt,documentoId);
            await traceCommand.ExecuteNonQueryAsync(cancellationToken);
        }
        if(result.CausacionServicioId is not null)
        {
            await using var retentionCommand=connection.CreateCommand();
            retentionCommand.CommandType=CommandType.StoredProcedure;
            retentionCommand.CommandText="comp.usp_AplicarRetencionesCausacionDocumento";
            Add(retentionCommand,"@EmpresaId",SqlDbType.BigInt,empresaId);
            Add(retentionCommand,"@DocumentoProveedorId",SqlDbType.BigInt,documentoId);
            await retentionCommand.ExecuteNonQueryAsync(cancellationToken);
        }
        return result;
    }

    public async Task<IReadOnlyList<AccountingPeriodResponse>> GetAccountingPeriodsAsync(long empresaId,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT PeriodoContableId,Codigo,FechaInicio,FechaFin,Estado
            FROM core.PeriodoContable
            WHERE EmpresaId=@EmpresaId AND Estado IN('ABIERTO','REABIERTO')
            ORDER BY FechaInicio DESC;
            """;
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);
        var result=new List<AccountingPeriodResponse>();
        while(await reader.ReadAsync(cancellationToken)) result.Add(new(reader.GetInt64(0),reader.GetString(1),DateOnly.FromDateTime(reader.GetDateTime(2)),DateOnly.FromDateTime(reader.GetDateTime(3)),reader.GetString(4)));
        return result;
    }

    public async Task<IReadOnlyList<AccountingAccountResponse>> GetAccountingAccountsAsync(long empresaId,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT CuentaContableId,Codigo,Nombre,Tipo,Naturaleza
            FROM cont.CuentaContable
            WHERE EmpresaId=@EmpresaId AND Activa=1 AND PermiteMovimiento=1
            ORDER BY Codigo;
            """;
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);
        var result=new List<AccountingAccountResponse>();
        while(await reader.ReadAsync(cancellationToken)) result.Add(new(reader.GetInt64(0),reader.GetString(1),reader.GetString(2),reader.GetString(3),reader.GetString(4)));
        return result;
    }

    public async Task<ServiceAccrualWorkflowResponse?> GetServiceAccrualAsync(long empresaId,long causacionId,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        long id; string numero; string estado; DateOnly fecha; string documento; string proveedor; string? centro; string? proyecto; long? periodo; long? comprobante; decimal baseTotal; decimal impuestos; decimal retenciones;
        await using(var command=connection.CreateCommand())
        {
            command.CommandText="""
                SELECT c.CausacionServicioId,c.Numero,c.Estado,c.FechaContable,d.NumeroDocumento,t.RazonSocial,
                       c.CentroCostoCodigo,c.ProyectoCodigo,c.PeriodoContableId,c.ComprobanteContableId,
                       COALESCE(SUM(l.Base),0),COALESCE(SUM(l.Impuestos),0),COALESCE(SUM(l.Retenciones),0)
                FROM comp.CausacionServicio c
                JOIN comp.DocumentoProveedor d ON d.EmpresaId=c.EmpresaId AND d.DocumentoProveedorId=c.DocumentoProveedorId
                JOIN ter.Tercero t ON t.EmpresaId=c.EmpresaId AND t.TerceroId=c.TerceroId
                LEFT JOIN comp.CausacionServicioLinea l ON l.EmpresaId=c.EmpresaId AND l.CausacionServicioId=c.CausacionServicioId
                WHERE c.EmpresaId=@EmpresaId AND c.CausacionServicioId=@CausacionServicioId
                GROUP BY c.CausacionServicioId,c.Numero,c.Estado,c.FechaContable,d.NumeroDocumento,t.RazonSocial,c.CentroCostoCodigo,c.ProyectoCodigo,c.PeriodoContableId,c.ComprobanteContableId;
                """;
            Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId); Add(command,"@CausacionServicioId",SqlDbType.BigInt,causacionId);
            await using var reader=await command.ExecuteReaderAsync(cancellationToken);
            if(!await reader.ReadAsync(cancellationToken)) return null;
            id=reader.GetInt64(0); numero=reader.GetString(1); estado=reader.GetString(2); fecha=DateOnly.FromDateTime(reader.GetDateTime(3)); documento=reader.GetString(4); proveedor=reader.GetString(5);
            centro=reader.IsDBNull(6)?null:reader.GetString(6); proyecto=reader.IsDBNull(7)?null:reader.GetString(7); periodo=reader.IsDBNull(8)?null:reader.GetInt64(8); comprobante=reader.IsDBNull(9)?null:reader.GetInt64(9);
            baseTotal=reader.GetDecimal(10); impuestos=reader.GetDecimal(11); retenciones=reader.GetDecimal(12);
        }
        var lines=new List<ServiceAccrualLineResponse>();
        await using(var command=connection.CreateCommand())
        {
            command.CommandText="SELECT NumeroLinea,Descripcion,CuentaContableCodigo,Base,Impuestos,Retenciones,Total FROM comp.CausacionServicioLinea WHERE EmpresaId=@EmpresaId AND CausacionServicioId=@CausacionServicioId ORDER BY NumeroLinea;";
            Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId); Add(command,"@CausacionServicioId",SqlDbType.BigInt,causacionId);
            await using var reader=await command.ExecuteReaderAsync(cancellationToken);
            while(await reader.ReadAsync(cancellationToken)) lines.Add(new(reader.GetInt32(0),reader.GetString(1),reader.IsDBNull(2)?null:reader.GetString(2),reader.GetDecimal(3),reader.GetDecimal(4),reader.GetDecimal(5),reader.GetDecimal(6)));
        }
        var entries=new List<AccountingEntryLineResponse>();
        if(comprobante is not null)
        {
            await using var command=connection.CreateCommand();
            command.CommandText="""
                SELECT l.NumeroLinea,c.Codigo,c.Nombre,l.Descripcion,l.Debito,l.Credito,l.CentroCostoCodigo,l.ProyectoCodigo
                FROM cont.ComprobanteContableLinea l JOIN cont.CuentaContable c ON c.EmpresaId=l.EmpresaId AND c.CuentaContableId=l.CuentaContableId
                WHERE l.EmpresaId=@EmpresaId AND l.ComprobanteContableId=@ComprobanteContableId ORDER BY l.NumeroLinea;
                """;
            Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId); Add(command,"@ComprobanteContableId",SqlDbType.BigInt,comprobante);
            await using var reader=await command.ExecuteReaderAsync(cancellationToken);
            while(await reader.ReadAsync(cancellationToken)) entries.Add(new(reader.GetInt32(0),reader.GetString(1),reader.GetString(2),reader.GetString(3),reader.GetDecimal(4),reader.GetDecimal(5),reader.IsDBNull(6)?null:reader.GetString(6),reader.IsDBNull(7)?null:reader.GetString(7)));
        }
        return new(id,numero,estado,fecha,documento,proveedor,centro,proyecto,periodo,comprobante,baseTotal,impuestos,retenciones,baseTotal+impuestos-retenciones,lines,entries);
    }

    public async Task<PostedReceiptResponse> PostReceiptAsync(long empresaId,long recepcionId,PostReceiptRequest input,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandType=CommandType.StoredProcedure;
        command.CommandText="inv.usp_ContabilizarRecepcion";
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);
        Add(command,"@RecepcionMercanciaId",SqlDbType.BigInt,recepcionId);
        Add(command,"@UsuarioId",SqlDbType.BigInt,input.UsuarioId);
        Add(command,"@CorrelationId",SqlDbType.UniqueIdentifier,input.CorrelationId);
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);
        if(!await reader.ReadAsync(cancellationToken)) throw new InvalidOperationException("No se obtuvo el resultado de la recepción.");
        return new(reader.GetInt64(0),reader.GetString(1),reader.GetInt32(2),reader.GetBoolean(3));
    }

    public async Task<PostedServiceAccrualResponse> PostServiceAccrualAsync(long empresaId,long causacionId,PostServiceAccrualRequest input,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandType=CommandType.StoredProcedure;
        command.CommandText="comp.usp_ContabilizarCausacionServicio";
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);
        Add(command,"@CausacionServicioId",SqlDbType.BigInt,causacionId);
        Add(command,"@PeriodoContableId",SqlDbType.BigInt,input.PeriodoContableId);
        Add(command,"@CuentaImpuestoCodigo",SqlDbType.NVarChar,input.CuentaImpuestoCodigo,30);
        Add(command,"@CuentaRetencionCodigo",SqlDbType.NVarChar,input.CuentaRetencionCodigo,30);
        Add(command,"@CuentaPorPagarCodigo",SqlDbType.NVarChar,input.CuentaPorPagarCodigo,30);
        Add(command,"@UsuarioId",SqlDbType.BigInt,input.UsuarioId);
        Add(command,"@CorrelationId",SqlDbType.UniqueIdentifier,input.CorrelationId);
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);
        if(!await reader.ReadAsync(cancellationToken)) throw new InvalidOperationException("No se obtuvo el resultado de la causación.");
        return new(reader.GetInt64(0),reader.GetInt64(1),reader.GetString(2),reader.GetBoolean(3));
    }

    public async Task<AssignedServiceAccountsResponse> AssignServiceAccountsAsync(long empresaId,long causacionId,AssignServiceAccountsRequest input,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandType=CommandType.StoredProcedure;
        command.CommandText="comp.usp_AsignarCuentasCausacion";
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);
        Add(command,"@CausacionServicioId",SqlDbType.BigInt,causacionId);
        Add(command,"@CentroCostoCodigo",SqlDbType.NVarChar,input.CentroCostoCodigo,50);
        Add(command,"@ProyectoCodigo",SqlDbType.NVarChar,input.ProyectoCodigo,50);
        Add(command,"@LineasJson",SqlDbType.NVarChar,JsonSerializer.Serialize(input.Lineas.Select(x=>new { numeroLinea=x.NumeroLinea,cuentaContableCodigo=x.CuentaContableCodigo })),-1);
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);
        if(!await reader.ReadAsync(cancellationToken)) throw new InvalidOperationException("No se obtuvo el resultado de la asignación contable.");
        return new(reader.GetInt64(0),reader.GetString(1));
    }

    private static string MapClassification(string value) => Classifications.TryGetValue(value,out var mapped)
        ? mapped : throw new ArgumentException($"Clasificación no soportada: {value}.",nameof(value));

    private static void Add(SqlCommand command,string name,SqlDbType type,object? value,int size=0)
    {
        var parameter=size!=0?new SqlParameter(name,type,size):new SqlParameter(name,type);
        parameter.Value=value??DBNull.Value;
        command.Parameters.Add(parameter);
    }

    private static void AddDecimal(SqlCommand command,string name,decimal value,byte precision,byte scale)
        => command.Parameters.Add(new SqlParameter(name,SqlDbType.Decimal){Precision=precision,Scale=scale,Value=value});
}
