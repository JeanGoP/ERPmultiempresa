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
            ["factorAUnidadBase"] = line.FactorAUnidadBase,
            ["precioUnitario"] = line.PrecioUnitario,
            ["subtotalBruto"] = line.SubtotalBruto,
            ["descuento"] = line.Descuento,
            ["impuesto"] = line.Impuesto,
            ["cargo"] = line.Cargo,
            ["retencion"] = line.Retencion,
            ["totalNeto"] = line.TotalNeto
        });
        var lineasJson = JsonSerializer.Serialize(linePayload);
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
                WHERE d.EmpresaId=@EmpresaId AND t.NumeroIdentificacion=@ProveedorIdentificacion
                  AND d.TipoDocumento=@TipoDocumento AND d.NumeroDocumento=@NumeroDocumento;
                """;
            Add(existing,"@EmpresaId",SqlDbType.BigInt,empresaId);
            Add(existing,"@ProveedorIdentificacion",SqlDbType.NVarChar,input.ProveedorIdentificacion,30);
            Add(existing,"@TipoDocumento",SqlDbType.VarChar,input.TipoDocumento,20);
            Add(existing,"@NumeroDocumento",SqlDbType.NVarChar,input.NumeroDocumento,50);
            var existingId=await existing.ExecuteScalarAsync(cancellationToken);
            if(existingId is not null and not DBNull) return new(Convert.ToInt64(existingId),true);
        }
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(cancellationToken);
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
        return new(documentoId,yaExistia);
    }

    public async Task<SupplierDocumentWorkflowResponse?> GetWorkflowAsync(long empresaId,long documentoId,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT d.DocumentoProveedorId,d.Estado,d.TipoDocumento,d.NumeroDocumento,t.RazonSocial,t.NumeroIdentificacion,
                   d.FechaDocumento,d.FechaVencimiento,d.Moneda,d.CufeCude,d.HashXml,
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
            DateOnly.FromDateTime(reader.GetDateTime(6)),reader.IsDBNull(7)?null:DateOnly.FromDateTime(reader.GetDateTime(7)),reader.GetString(8),
            reader.IsDBNull(9)?null:reader.GetString(9),reader.IsDBNull(10)?null:reader.GetString(10),reader.GetBoolean(11),
            reader.GetDecimal(12),reader.GetDecimal(13),reader.GetDecimal(14),reader.GetDecimal(15),reader.GetDecimal(16),reader.GetInt32(17),reader.GetInt32(18),
            reader.IsDBNull(19)?null:reader.GetInt64(19),reader.IsDBNull(20)?null:reader.GetString(20),reader.IsDBNull(21)?null:reader.GetString(21),
            reader.IsDBNull(22)?null:reader.GetInt64(22),reader.IsDBNull(23)?null:reader.GetString(23),reader.IsDBNull(24)?null:reader.GetString(24));
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
