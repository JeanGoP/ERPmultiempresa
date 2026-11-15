using System.Data;
using System.Text.Json.Serialization;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Zeus;

namespace NexoERP.Api.Inventory;

public sealed record ReverseTransferRequest(long PeriodoInventarioId, DateOnly FechaContable, string Motivo);
public sealed record TransferPage(IReadOnlyList<TransferDocument> Items, int Page, int PageSize, long Total);
public sealed record TransferWarehouse(long Id, string Codigo, string Nombre);
public sealed record TransferCompany(string RazonSocial, string Nit, string? DigitoVerificacion);
public sealed record TransferSerial(string? Serial, string? Motor, string? Chasis, string? Vin);
public sealed record TransferLine(string Codigo, string Descripcion, decimal Cantidad, IReadOnlyList<TransferSerial> Unidades);
public sealed record TransferDocument(
    long TrasladoId, string Numero, string Estado, DateOnly? FechaContable, DateTime FechaSalida,
    TransferWarehouse BodegaOrigen, TransferWarehouse BodegaDestino,
    long? TrasladoOriginalId, string? NumeroOriginal, long? TrasladoReversionId, string? NumeroReversion,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] TransferCompany? Empresa = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? Observacion = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<TransferLine>? Lineas = null);

public sealed partial class InventoryOperationsRepository
{
    private const string TransferWarehouses = """
        FROM inv.Traslado t
        JOIN inv.Bodega bo ON bo.EmpresaId=t.EmpresaId AND bo.BodegaId=t.BodegaOrigenId
        JOIN inv.Bodega bd ON bd.EmpresaId=t.EmpresaId AND bd.BodegaId=t.BodegaDestinoId
        """;
    private const string TransferLinks = """
        LEFT JOIN inv.Traslado original ON original.EmpresaId=t.EmpresaId AND original.TrasladoId=t.TrasladoOriginalId
        LEFT JOIN inv.Traslado reversal ON reversal.EmpresaId=t.EmpresaId AND reversal.TrasladoOriginalId=t.TrasladoId
        """;
    private const string TransferColumns = """
        t.TrasladoId,t.Numero,t.Estado,COALESCE(t.FechaContableRecepcion,t.FechaContableSalida),t.FechaSalida,
        bo.BodegaId,bo.Codigo,bo.Nombre,bd.BodegaId,bd.Codigo,bd.Nombre,
        t.TrasladoOriginalId,original.Numero,reversal.TrasladoId,reversal.Numero
        """;

    public async Task<TransferPage> ListTransfersAsync(long company, string? search, int page, int pageSize, CancellationToken ct)
    {
        page = Math.Clamp(page, 1, int.MaxValue);
        pageSize = Math.Clamp(pageSize, 1, 100);
        search = search?.Trim();
        if (search?.Length > 120) search = search[..120];
        var pattern = string.IsNullOrEmpty(search) ? null : $"%{search.Replace("\\", "\\\\").Replace("%", "\\%").Replace("_", "\\_").Replace("[", "\\[")}%";
        const string filter = """
            WHERE t.EmpresaId=@Company AND (
                @Search IS NULL OR t.Numero COLLATE Latin1_General_100_CI_AI LIKE @Search ESCAPE '\'
                OR CONCAT(bo.Codigo,' ',bo.Nombre) COLLATE Latin1_General_100_CI_AI LIKE @Search ESCAPE '\'
                OR CONCAT(bd.Codigo,' ',bd.Nombre) COLLATE Latin1_General_100_CI_AI LIKE @Search ESCAPE '\'
                OR EXISTS (
                    SELECT 1 FROM inv.TrasladoLinea l
                    JOIN inv.Articulo a ON a.EmpresaId=l.EmpresaId AND a.ArticuloId=l.ArticuloId
                    WHERE l.EmpresaId=t.EmpresaId AND l.TrasladoId=t.TrasladoId
                    AND (CONCAT(a.Codigo,' ',a.Descripcion) COLLATE Latin1_General_100_CI_AI LIKE @Search ESCAPE '\'
                        OR EXISTS (
                            SELECT 1 FROM inv.TrasladoLineaUnidad u
                            JOIN inv.UnidadIdentificador k ON k.EmpresaId=u.EmpresaId AND k.UnidadSerializadaId=u.UnidadSerializadaId
                            WHERE u.EmpresaId=l.EmpresaId AND u.TrasladoLineaId=l.TrasladoLineaId
                            AND k.Valor COLLATE Latin1_General_100_CI_AI LIKE @Search ESCAPE '\'
                        )
                    )
                )
            )
            """;
        await using var connection = await connections.OpenAsync(company, false, ct);
        await using var command = connection.CreateCommand();
        command.CommandText = $"""
            SELECT COUNT_BIG(*) {TransferWarehouses}
            {filter};
            SELECT {TransferColumns} {TransferWarehouses}
            {TransferLinks}
            {filter}
            ORDER BY t.FechaSalida DESC,t.TrasladoId DESC OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
            """;
        Add(command, "@Company", SqlDbType.BigInt, company);
        Add(command, "@Search", SqlDbType.NVarChar, pattern, 242);
        Add(command, "@Offset", SqlDbType.BigInt, (long)(page - 1) * pageSize);
        Add(command, "@PageSize", SqlDbType.Int, pageSize);
        var items = new List<TransferDocument>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        await reader.ReadAsync(ct);
        var total = reader.GetInt64(0);
        await reader.NextResultAsync(ct);
        while (await reader.ReadAsync(ct)) items.Add(ReadTransfer(reader));
        return new(items, page, pageSize, total);
    }

    public async Task<TransferDocument?> GetTransferAsync(long company, long transfer, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(company, false, ct);
        await using var command = connection.CreateCommand();
        command.CommandText = $"""
            SELECT {TransferColumns},t.Observacion,e.RazonSocial,e.Nit,e.DigitoVerificacion
            {TransferWarehouses}
            {TransferLinks}
            JOIN core.Empresa e ON e.EmpresaId=t.EmpresaId
            WHERE t.EmpresaId=@Company AND t.TrasladoId=@Transfer;

            SELECT l.TrasladoLineaId,a.Codigo,a.Descripcion,COALESCE(l.CantidadRecibida,l.CantidadDespachada),
                   u.UnidadSerializadaId,k.Serial,k.Motor,k.Chasis,k.Vin
            FROM inv.TrasladoLinea l
            JOIN inv.Articulo a ON a.EmpresaId=l.EmpresaId AND a.ArticuloId=l.ArticuloId
            LEFT JOIN inv.TrasladoLineaUnidad u ON u.EmpresaId=l.EmpresaId AND u.TrasladoLineaId=l.TrasladoLineaId
            OUTER APPLY (
                SELECT MAX(CASE WHEN i.Tipo='SERIAL' THEN i.Valor END) Serial,MAX(CASE WHEN i.Tipo='MOTOR' THEN i.Valor END) Motor,
                       MAX(CASE WHEN i.Tipo='CHASIS' THEN i.Valor END) Chasis,MAX(CASE WHEN i.Tipo='VIN' THEN i.Valor END) Vin
                FROM inv.UnidadIdentificador i
                WHERE i.EmpresaId=u.EmpresaId AND i.UnidadSerializadaId=u.UnidadSerializadaId
            ) k
            WHERE l.EmpresaId=@Company AND l.TrasladoId=@Transfer
            ORDER BY l.NumeroLinea,u.UnidadSerializadaId;
            """;
        Add(command, "@Company", SqlDbType.BigInt, company);
        Add(command, "@Transfer", SqlDbType.BigInt, transfer);
        await using var reader = await command.ExecuteReaderAsync(ct);
        if (!await reader.ReadAsync(ct)) return null;
        var lines = new List<TransferLine>();
        var document = ReadTransfer(reader) with
        {
            Observacion = NullableText(reader, 15),
            Empresa = new(reader.GetString(16), reader.GetString(17), NullableText(reader, 18)),
            Lineas = lines
        };
        await reader.NextResultAsync(ct);
        long? lineId = null;
        List<TransferSerial> serials = [];
        while (await reader.ReadAsync(ct))
        {
            if (reader.GetInt64(0) != lineId)
            {
                lineId = reader.GetInt64(0);
                serials = [];
                lines.Add(new(reader.GetString(1), reader.GetString(2), reader.GetDecimal(3), serials));
            }
            if (!reader.IsDBNull(4))
                serials.Add(new(NullableText(reader, 5), NullableText(reader, 6), NullableText(reader, 7), NullableText(reader, 8)));
        }
        return document;
    }

    public async Task<InventoryDocumentOperationResponse> ReverseTransferAsync(long company, long transfer, ReverseTransferRequest request, long user, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(company, false, ct);
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(ct);
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandType = CommandType.StoredProcedure;
        command.CommandText = "inv.usp_RevertirTraslado";
        Add(command, "@EmpresaId", SqlDbType.BigInt, company);
        Add(command, "@TrasladoId", SqlDbType.BigInt, transfer);
        Add(command, "@PeriodoInventarioId", SqlDbType.BigInt, request.PeriodoInventarioId);
        Add(command, "@FechaContable", SqlDbType.Date, request.FechaContable.ToDateTime(TimeOnly.MinValue));
        Add(command, "@Motivo", SqlDbType.NVarChar, request.Motivo.Trim(), 500);
        Add(command, "@UsuarioId", SqlDbType.BigInt, user);
        Add(command, "@CorrelationId", SqlDbType.UniqueIdentifier, Guid.NewGuid());
        var result = await ReadOperationAsync(command, ct);
        var posting = result.YaExistia
            ? await ZeusRepository.ReadTransferStatusAsync(connection, transaction, company, result.DocumentoId, ct)
            : await ZeusRepository.EnqueueTransferAsync(connection, transaction, company, result.DocumentoId, user, ct);
        await transaction.CommitAsync(ct);
        return result with { Zeus = posting };
    }

    private static TransferDocument ReadTransfer(SqlDataReader reader) => new(
        reader.GetInt64(0), reader.GetString(1), reader.GetString(2),
        reader.IsDBNull(3) ? null : DateOnly.FromDateTime(reader.GetDateTime(3)), reader.GetDateTime(4),
        new(reader.GetInt64(5), reader.GetString(6), reader.GetString(7)),
        new(reader.GetInt64(8), reader.GetString(9), reader.GetString(10)),
        reader.IsDBNull(11) ? null : reader.GetInt64(11), NullableText(reader, 12),
        reader.IsDBNull(13) ? null : reader.GetInt64(13), NullableText(reader, 14));

    private static string? NullableText(SqlDataReader reader, int ordinal) => reader.IsDBNull(ordinal) ? null : reader.GetString(ordinal);
}
