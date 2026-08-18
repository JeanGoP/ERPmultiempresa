using System.Data;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;

namespace NexoERP.Api.Inventory;

public sealed class InventoryRepository(TenantConnectionFactory connections)
{
    public async Task<IReadOnlyList<WarehouseResponse>> GetWarehousesAsync(long empresaId, CancellationToken cancellationToken)
    {
        await using var connection = await connections.OpenAsync(empresaId, false, cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT BodegaId, Codigo, Nombre, UsaUbicaciones, EsTransito
            FROM inv.Bodega
            WHERE EmpresaId=@EmpresaId AND Activa=1
            ORDER BY Nombre;
            """;
        command.Parameters.Add(new SqlParameter("@EmpresaId", SqlDbType.BigInt) { Value = empresaId });
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var result = new List<WarehouseResponse>();
        while (await reader.ReadAsync(cancellationToken))
            result.Add(new(reader.GetInt64(0), reader.GetString(1), reader.GetString(2), reader.GetBoolean(3), reader.GetBoolean(4)));
        return result;
    }

    public async Task<IReadOnlyList<InventoryPeriodListResponse>> GetPeriodsAsync(long empresaId,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT PeriodoInventarioId,Codigo,FechaInicio,FechaFin,Estado
            FROM core.PeriodoInventario
            WHERE EmpresaId=@EmpresaId AND Estado IN('ABIERTO','REABIERTO')
            ORDER BY FechaInicio DESC;
            """;
        command.Parameters.Add(new SqlParameter("@EmpresaId",SqlDbType.BigInt){Value=empresaId});
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);
        var result=new List<InventoryPeriodListResponse>();
        while(await reader.ReadAsync(cancellationToken)) result.Add(new(reader.GetInt64(0),reader.GetString(1),DateOnly.FromDateTime(reader.GetDateTime(2)),DateOnly.FromDateTime(reader.GetDateTime(3)),reader.GetString(4)));
        return result;
    }

    public async Task<IReadOnlyList<InventoryBalanceResponse>> GetBalancesAsync(long empresaId, CancellationToken cancellationToken)
    {
        await using var connection = await connections.OpenAsync(empresaId, false, cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT s.BodegaId, b.Nombre, s.ArticuloId, a.Codigo, a.Descripcion,
                   s.Existencia, s.ValorTotal, s.CostoPromedio
            FROM inv.SaldoArticuloBodega s
            JOIN inv.Bodega b ON b.EmpresaId=s.EmpresaId AND b.BodegaId=s.BodegaId
            JOIN inv.Articulo a ON a.EmpresaId=s.EmpresaId AND a.ArticuloId=s.ArticuloId
            WHERE s.EmpresaId=@EmpresaId
            ORDER BY b.Nombre, a.Codigo;
            """;
        command.Parameters.Add(new SqlParameter("@EmpresaId", SqlDbType.BigInt) { Value = empresaId });
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var result = new List<InventoryBalanceResponse>();
        while (await reader.ReadAsync(cancellationToken))
            result.Add(new(reader.GetInt64(0), reader.GetString(1), reader.GetInt64(2), reader.GetString(3), reader.GetString(4), reader.GetDecimal(5), reader.GetDecimal(6), reader.GetDecimal(7)));
        return result;
    }

    public async Task<IReadOnlyList<DetailedInventoryBalanceResponse>> GetDetailedBalancesAsync(long empresaId,long? bodegaId,string? q,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken); await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT m.BodegaId,b.Nombre,m.UbicacionId,u.Codigo,m.ArticuloId,a.Codigo,a.Descripcion,m.LoteId,l.NumeroLote,l.FechaVencimiento,
                   SUM(m.CantidadEntrada-m.CantidadSalida),SUM(CASE WHEN m.CantidadEntrada>0 THEN m.ValorMovimiento ELSE -m.ValorMovimiento END)
            FROM inv.MovimientoInventario m JOIN inv.Bodega b ON b.EmpresaId=m.EmpresaId AND b.BodegaId=m.BodegaId JOIN inv.Articulo a ON a.EmpresaId=m.EmpresaId AND a.ArticuloId=m.ArticuloId
            LEFT JOIN inv.Ubicacion u ON u.EmpresaId=m.EmpresaId AND u.UbicacionId=m.UbicacionId LEFT JOIN inv.Lote l ON l.EmpresaId=m.EmpresaId AND l.LoteId=m.LoteId
            WHERE m.EmpresaId=@EmpresaId AND (@BodegaId IS NULL OR m.BodegaId=@BodegaId) AND (@Q IS NULL OR a.Codigo LIKE '%'+@Q+'%' OR a.Descripcion LIKE '%'+@Q+'%' OR l.NumeroLote LIKE '%'+@Q+'%')
            GROUP BY m.BodegaId,b.Nombre,m.UbicacionId,u.Codigo,m.ArticuloId,a.Codigo,a.Descripcion,m.LoteId,l.NumeroLote,l.FechaVencimiento HAVING SUM(m.CantidadEntrada-m.CantidadSalida)<>0
            ORDER BY b.Nombre,a.Codigo,l.FechaVencimiento,l.NumeroLote,u.Codigo;
            """;
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(command,"@BodegaId",SqlDbType.BigInt,bodegaId);Add(command,"@Q",SqlDbType.NVarChar,string.IsNullOrWhiteSpace(q)?null:q.Trim(),120);
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);var result=new List<DetailedInventoryBalanceResponse>();
        while(await reader.ReadAsync(cancellationToken)){var quantity=reader.GetDecimal(10);var value=reader.GetDecimal(11);result.Add(new(reader.GetInt64(0),reader.GetString(1),reader.IsDBNull(2)?null:reader.GetInt64(2),reader.IsDBNull(3)?null:reader.GetString(3),reader.GetInt64(4),reader.GetString(5),reader.GetString(6),reader.IsDBNull(7)?null:reader.GetInt64(7),reader.IsDBNull(8)?null:reader.GetString(8),reader.IsDBNull(9)?null:DateOnly.FromDateTime(reader.GetDateTime(9)),quantity,value,quantity==0?0:value/quantity));}return result;
    }

    public async Task<IReadOnlyList<KardexMovementResponse>> GetKardexAsync(long empresaId,DateOnly? desde,DateOnly? hasta,long? bodegaId,long? articuloId,string? q,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);await using var command=connection.CreateCommand();command.CommandText="""
            SELECT m.MovimientoInventarioId,m.FechaMovimiento,m.FechaContable,m.TipoMovimiento,m.NumeroDocumento,m.BodegaId,b.Nombre,m.ArticuloId,a.Codigo,a.Descripcion,l.NumeroLote,m.CantidadEntrada,m.CantidadSalida,m.CostoUnitarioMovimiento,m.ValorMovimiento,m.ExistenciaPosterior,m.CostoPromedioPosterior
            FROM inv.MovimientoInventario m JOIN inv.Bodega b ON b.EmpresaId=m.EmpresaId AND b.BodegaId=m.BodegaId JOIN inv.Articulo a ON a.EmpresaId=m.EmpresaId AND a.ArticuloId=m.ArticuloId LEFT JOIN inv.Lote l ON l.EmpresaId=m.EmpresaId AND l.LoteId=m.LoteId
            WHERE m.EmpresaId=@EmpresaId AND (@Desde IS NULL OR m.FechaContable>=@Desde) AND (@Hasta IS NULL OR m.FechaContable<=@Hasta) AND (@BodegaId IS NULL OR m.BodegaId=@BodegaId) AND (@ArticuloId IS NULL OR m.ArticuloId=@ArticuloId) AND (@Q IS NULL OR a.Codigo LIKE '%'+@Q+'%' OR a.Descripcion LIKE '%'+@Q+'%' OR m.NumeroDocumento LIKE '%'+@Q+'%') ORDER BY m.FechaContable DESC,m.MovimientoInventarioId DESC;
            """;Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(command,"@Desde",SqlDbType.Date,desde?.ToDateTime(TimeOnly.MinValue));Add(command,"@Hasta",SqlDbType.Date,hasta?.ToDateTime(TimeOnly.MinValue));Add(command,"@BodegaId",SqlDbType.BigInt,bodegaId);Add(command,"@ArticuloId",SqlDbType.BigInt,articuloId);Add(command,"@Q",SqlDbType.NVarChar,string.IsNullOrWhiteSpace(q)?null:q.Trim(),120);
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);var result=new List<KardexMovementResponse>();while(await reader.ReadAsync(cancellationToken))result.Add(new(reader.GetInt64(0),reader.GetDateTime(1),DateOnly.FromDateTime(reader.GetDateTime(2)),reader.GetString(3),reader.GetString(4),reader.GetInt64(5),reader.GetString(6),reader.GetInt64(7),reader.GetString(8),reader.GetString(9),reader.IsDBNull(10)?null:reader.GetString(10),reader.GetDecimal(11),reader.GetDecimal(12),reader.GetDecimal(13),reader.GetDecimal(14),reader.GetDecimal(15),reader.GetDecimal(16)));return result;
    }

    public async Task<IReadOnlyList<ExpiryAlertResponse>> GetExpiryAlertsAsync(long empresaId,int days,long? bodegaId,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);await using var command=connection.CreateCommand();command.CommandText="""
            SELECT m.BodegaId,b.Nombre,m.ArticuloId,a.Codigo,a.Descripcion,l.LoteId,l.NumeroLote,l.FechaVencimiento,DATEDIFF(day,CONVERT(date,GETDATE()),l.FechaVencimiento),SUM(m.CantidadEntrada-m.CantidadSalida)
            FROM inv.MovimientoInventario m JOIN inv.Bodega b ON b.EmpresaId=m.EmpresaId AND b.BodegaId=m.BodegaId JOIN inv.Articulo a ON a.EmpresaId=m.EmpresaId AND a.ArticuloId=m.ArticuloId JOIN inv.Lote l ON l.EmpresaId=m.EmpresaId AND l.LoteId=m.LoteId
            WHERE m.EmpresaId=@EmpresaId AND (@BodegaId IS NULL OR m.BodegaId=@BodegaId) AND l.FechaVencimiento<=DATEADD(day,@Days,CONVERT(date,GETDATE())) GROUP BY m.BodegaId,b.Nombre,m.ArticuloId,a.Codigo,a.Descripcion,l.LoteId,l.NumeroLote,l.FechaVencimiento HAVING SUM(m.CantidadEntrada-m.CantidadSalida)>0 ORDER BY l.FechaVencimiento,b.Nombre,a.Codigo;
            """;Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId);Add(command,"@BodegaId",SqlDbType.BigInt,bodegaId);Add(command,"@Days",SqlDbType.Int,Math.Clamp(days,0,3650));await using var reader=await command.ExecuteReaderAsync(cancellationToken);var result=new List<ExpiryAlertResponse>();while(await reader.ReadAsync(cancellationToken)){var remaining=reader.GetInt32(8);result.Add(new(reader.GetInt64(0),reader.GetString(1),reader.GetInt64(2),reader.GetString(3),reader.GetString(4),reader.GetInt64(5),reader.GetString(6),DateOnly.FromDateTime(reader.GetDateTime(7)),remaining,remaining<0?"VENCIDO":remaining<=30?"CRITICO":"PROXIMO",reader.GetDecimal(9)));}return result;
    }

    public async Task<InventoryMovementResponse> PostEntryAsync(long empresaId, PostInventoryEntryRequest input, CancellationToken cancellationToken)
    {
        await using var connection = await connections.OpenAsync(empresaId, false, cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandType = CommandType.StoredProcedure;
        command.CommandText = "inv.usp_ContabilizarEntrada";
        command.CommandTimeout = 30;

        Add(command, "@EmpresaId", SqlDbType.BigInt, empresaId);
        Add(command, "@BodegaId", SqlDbType.BigInt, input.BodegaId);
        Add(command, "@UbicacionId", SqlDbType.BigInt, input.UbicacionId);
        Add(command, "@ArticuloId", SqlDbType.BigInt, input.ArticuloId);
        Add(command, "@LoteId", SqlDbType.BigInt, input.LoteId);
        Add(command, "@PeriodoInventarioId", SqlDbType.BigInt, input.PeriodoInventarioId);
        Add(command, "@FechaMovimiento", SqlDbType.DateTime2, input.FechaMovimiento);
        Add(command, "@FechaContable", SqlDbType.Date, input.FechaContable.ToDateTime(TimeOnly.MinValue));
        Add(command, "@TipoMovimiento", SqlDbType.VarChar, input.TipoMovimiento, 30);
        Add(command, "@ModuloOrigen", SqlDbType.VarChar, input.ModuloOrigen, 30);
        Add(command, "@TipoDocumentoOrigen", SqlDbType.VarChar, input.TipoDocumentoOrigen, 40);
        Add(command, "@DocumentoOrigenId", SqlDbType.BigInt, input.DocumentoOrigenId);
        Add(command, "@DocumentoLineaOrigenId", SqlDbType.BigInt, input.DocumentoLineaOrigenId);
        Add(command, "@NumeroDocumento", SqlDbType.NVarChar, input.NumeroDocumento, 50);
        Add(command, "@TerceroId", SqlDbType.BigInt, input.TerceroId);
        AddDecimal(command, "@CantidadEntrada", input.Cantidad, 20, 6);
        AddDecimal(command, "@CostoUnitarioEntrada", input.CostoUnitario, 20, 8);
        Add(command, "@IdempotencyKey", SqlDbType.UniqueIdentifier, input.IdempotencyKey);
        Add(command, "@UsuarioId", SqlDbType.BigInt, input.UsuarioId);
        Add(command, "@CorrelationId", SqlDbType.UniqueIdentifier, input.CorrelationId);
        Add(command, "@MovimientoRelacionadoId", SqlDbType.BigInt, input.MovimientoRelacionadoId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken)) throw new InvalidOperationException("El motor de Kardex no devolvió resultado.");
        return new(reader.GetInt64(0), reader.GetDecimal(1), reader.GetDecimal(2), reader.GetDecimal(3), reader.GetBoolean(4));
    }

    public async Task<IReadOnlyList<HistoricalInventoryResponse>> GetInventoryAtAsync(long empresaId,DateOnly fecha,long? bodegaId,long? articuloId,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandType=CommandType.StoredProcedure; command.CommandText="inv.usp_ConsultarInventarioAFecha";
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId); Add(command,"@FechaCorte",SqlDbType.Date,fecha.ToDateTime(TimeOnly.MinValue));
        Add(command,"@BodegaId",SqlDbType.BigInt,bodegaId); Add(command,"@ArticuloId",SqlDbType.BigInt,articuloId);
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);
        var result=new List<HistoricalInventoryResponse>();
        while(await reader.ReadAsync(cancellationToken)) result.Add(new(reader.GetInt64(0),reader.GetInt64(1),reader.GetString(2),reader.GetString(3),reader.GetDecimal(4),reader.GetDecimal(5),reader.GetDecimal(6)));
        return result;
    }

    public async Task<IReadOnlyList<SerializedUnitResponse>> GetSerializedUnitsAsync(long empresaId,long? bodegaId,string? estado,string? q,CancellationToken cancellationToken)
    {
        await using var connection=await connections.OpenAsync(empresaId,false,cancellationToken);
        await using var command=connection.CreateCommand();
        command.CommandText="""
            SELECT s.UnidadSerializadaId,s.UnidadGuid,s.ArticuloId,a.Codigo,a.Descripcion,s.Estado,s.BodegaActualId,b.Nombre,
                   MAX(CASE WHEN i.Tipo='SERIAL' THEN i.Valor END),MAX(CASE WHEN i.Tipo='MOTOR' THEN i.Valor END),
                   MAX(CASE WHEN i.Tipo='CHASIS' THEN i.Valor END),MAX(CASE WHEN i.Tipo='VIN' THEN i.Valor END),MAX(CASE WHEN i.Tipo='PLACA' THEN i.Valor END)
            FROM inv.UnidadSerializada s JOIN inv.Articulo a ON a.EmpresaId=s.EmpresaId AND a.ArticuloId=s.ArticuloId
            LEFT JOIN inv.Bodega b ON b.EmpresaId=s.EmpresaId AND b.BodegaId=s.BodegaActualId
            LEFT JOIN inv.UnidadIdentificador i ON i.EmpresaId=s.EmpresaId AND i.UnidadSerializadaId=s.UnidadSerializadaId
            WHERE s.EmpresaId=@EmpresaId AND (@BodegaId IS NULL OR s.BodegaActualId=@BodegaId) AND (@Estado IS NULL OR s.Estado=@Estado)
              AND (@Q IS NULL OR a.Codigo LIKE '%'+@Q+'%' OR a.Descripcion LIKE '%'+@Q+'%' OR EXISTS(SELECT 1 FROM inv.UnidadIdentificador f WHERE f.EmpresaId=s.EmpresaId AND f.UnidadSerializadaId=s.UnidadSerializadaId AND f.Valor LIKE '%'+@Q+'%'))
            GROUP BY s.UnidadSerializadaId,s.UnidadGuid,s.ArticuloId,a.Codigo,a.Descripcion,s.Estado,s.BodegaActualId,b.Nombre
            ORDER BY a.Codigo,s.UnidadSerializadaId;
            """;
        Add(command,"@EmpresaId",SqlDbType.BigInt,empresaId); Add(command,"@BodegaId",SqlDbType.BigInt,bodegaId); Add(command,"@Estado",SqlDbType.VarChar,string.IsNullOrWhiteSpace(estado)?null:estado,20);Add(command,"@Q",SqlDbType.NVarChar,string.IsNullOrWhiteSpace(q)?null:q.Trim(),120);
        await using var reader=await command.ExecuteReaderAsync(cancellationToken);
        var result=new List<SerializedUnitResponse>();
        while(await reader.ReadAsync(cancellationToken)) result.Add(new(reader.GetInt64(0),reader.GetGuid(1),reader.GetInt64(2),reader.GetString(3),reader.GetString(4),reader.GetString(5),reader.IsDBNull(6)?null:reader.GetInt64(6),reader.IsDBNull(7)?null:reader.GetString(7),reader.IsDBNull(8)?null:reader.GetString(8),reader.IsDBNull(9)?null:reader.GetString(9),reader.IsDBNull(10)?null:reader.GetString(10),reader.IsDBNull(11)?null:reader.GetString(11),reader.IsDBNull(12)?null:reader.GetString(12)));
        return result;
    }

    private static void Add(SqlCommand command, string name, SqlDbType type, object? value, int size = 0)
    {
        var parameter = size > 0 ? new SqlParameter(name, type, size) : new SqlParameter(name, type);
        parameter.Value = value ?? DBNull.Value;
        command.Parameters.Add(parameter);
    }

    private static void AddDecimal(SqlCommand command, string name, decimal value, byte precision, byte scale)
    {
        command.Parameters.Add(new SqlParameter(name, SqlDbType.Decimal) { Precision = precision, Scale = scale, Value = value });
    }
}
