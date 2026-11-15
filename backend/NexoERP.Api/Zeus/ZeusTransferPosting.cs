using System.Text.Json;
using Microsoft.Data.SqlClient;

namespace NexoERP.Api.Zeus;

public sealed partial class ZeusRepository
{
    private const string WaitingForOriginalTransfer = "La reversión se enviará cuando el traslado original quede contabilizado en Zeus.";

    internal static async Task<ZeusPostingStatus> EnqueueTransferAsync(SqlConnection connection,SqlTransaction transaction,
        long company,long transfer,long? user,CancellationToken ct)
    {
        await using var command = Command(connection,"""
            SELECT Estado,TrasladoOriginalId FROM inv.Traslado WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND TrasladoId=@Transfer;
            """,company,transaction);
        Add(command,"@Transfer",transfer);
        long? original;
        await using (var row = await command.ExecuteReaderAsync(ct))
        {
            if (!await row.ReadAsync(ct) || row.GetString(0) is not ("RECIBIDO" or "REVERTIDO"))
                throw new ArgumentException("El traslado debe estar recibido en Nexo antes de contabilizarlo en Zeus.");
            original = row.IsDBNull(1) ? null : row.GetInt64(1);
        }

        command.CommandText = "SELECT Estado FROM core.ZeusTrasladoEnvio WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND TrasladoId=@Transfer;";
        var current = await command.ExecuteScalarAsync(ct) as string;
        if (current is not null and not ("REQUIERE_REVISION" or "RECHAZADO"))
            return new(current,$"Zeus: {current}. Consulta Seguimiento para ver el comprobante.");

        ZeusSnapshot? snapshot = null;
        string? error = null;
        try
        {
            snapshot = original is null
                ? await BuildTransferAsync(connection,transaction,company,transfer,ct)
                : await BuildTransferReversalAsync(connection,transaction,company,transfer,original.Value,ct);
        }
        catch (ArgumentException exception) { error = exception.Message; }

        var state = snapshot is null ? "REQUIERE_REVISION" : "PENDIENTE";
        Add(command,"@Estado",state);
        Add(command,"@Snapshot",snapshot is null ? DBNull.Value : SerializeSnapshot(snapshot));
        Add(command,"@Error",(object?)error ?? DBNull.Value);
        Add(command,"@User",(object?)user ?? DBNull.Value);
        command.CommandText = """
            UPDATE core.ZeusTrasladoEnvio SET Estado=@Estado,Snapshot=@Snapshot,Error=@Error,ActualizadoEnUtc=SYSUTCDATETIME()
            WHERE EmpresaId=@E AND TrasladoId=@Transfer;
            IF @@ROWCOUNT=0
                INSERT core.ZeusTrasladoEnvio(EmpresaId,TrasladoId,Estado,Snapshot,Error)
                VALUES(@E,@Transfer,@Estado,@Snapshot,@Error);
            INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
            VALUES(@E,@User,'ZEUS_PREPARAR_TRASLADO','inv.Traslado',CONVERT(nvarchar(100),@Transfer),
                (SELECT @Estado estado,@Error error FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),'ZEUS');
            """;
        await command.ExecuteNonQueryAsync(ct);
        return new(state,error switch
        {
            null => "Envío contable a Zeus registrado. Consulta Seguimiento.",
            WaitingForOriginalTransfer => WaitingForOriginalTransfer,
            _ => $"Zeus requiere revisión. {error}"
        });
    }

    private static async Task<ZeusSnapshot> BuildTransferAsync(SqlConnection connection,SqlTransaction transaction,
        long company,long transfer,CancellationToken ct)
    {
        await using var command = Command(connection,"""
            SELECT t.Numero,t.FechaContableRecepcion,t.Observacion,
                o.BodegaId,o.Codigo,o.Nombre,d.BodegaId,d.Codigo,d.Nombre,o.SucursalId,s.Nombre,
                z.Configuracion,zo.Configuracion,zo.Servidor,zo.BaseDatos,zd.Configuracion,zd.Servidor,zd.BaseDatos,
                costs.Lineas,costs.Salidas,costs.Entradas,costs.ValorSalida,costs.ValorEntrada
            FROM inv.Traslado t
            JOIN inv.Bodega o ON o.EmpresaId=t.EmpresaId AND o.BodegaId=t.BodegaOrigenId
            JOIN inv.Bodega d ON d.EmpresaId=t.EmpresaId AND d.BodegaId=t.BodegaDestinoId
            LEFT JOIN core.Sucursal s ON s.EmpresaId=o.EmpresaId AND s.SucursalId=o.SucursalId
            LEFT JOIN core.ZeusConfiguracion z ON z.EmpresaId=t.EmpresaId
            LEFT JOIN core.ZeusBodegaCuenta zo ON zo.EmpresaId=t.EmpresaId AND zo.BodegaId=o.BodegaId
            LEFT JOIN core.ZeusBodegaCuenta zd ON zd.EmpresaId=t.EmpresaId AND zd.BodegaId=d.BodegaId
            CROSS APPLY (
                SELECT COUNT_BIG(*) Lineas,COUNT_BIG(mo.MovimientoInventarioId) Salidas,COUNT_BIG(md.MovimientoInventarioId) Entradas,
                    COALESCE(SUM(mo.ValorMovimiento),0) ValorSalida,COALESCE(SUM(md.ValorMovimiento),0) ValorEntrada
                FROM inv.TrasladoLinea l
                LEFT JOIN inv.MovimientoInventario mo ON mo.EmpresaId=l.EmpresaId AND mo.IdempotencyKey=l.SalidaOrigenKey
                    AND mo.BodegaId=o.BodegaId AND mo.TipoMovimiento='TRASLADO_SALIDA'
                LEFT JOIN inv.MovimientoInventario md ON md.EmpresaId=l.EmpresaId AND md.IdempotencyKey=l.EntradaDestinoKey
                    AND md.BodegaId=d.BodegaId AND md.TipoMovimiento='TRASLADO_ENTRADA'
                WHERE l.EmpresaId=t.EmpresaId AND l.TrasladoId=t.TrasladoId
            ) costs
            WHERE t.EmpresaId=@E AND t.TrasladoId=@Transfer AND t.Estado IN('RECIBIDO','REVERTIDO');
            """,company,transaction);
        Add(command,"@Transfer",transfer);
        await using var reader = await command.ExecuteReaderAsync(ct);
        if (!await reader.ReadAsync(ct) || reader.IsDBNull(1))
            throw new ArgumentException("No se encontró la fecha contable de recepción del traslado.");
        if (reader.IsDBNull(11) || JsonSerializer.Deserialize<ZeusSettings>(reader.GetString(11)) is not { Habilitado:true } settings)
            throw new ArgumentException("Habilita la integración contable con Zeus para esta empresa.");
        if (reader.IsDBNull(9) || reader.IsDBNull(10))
            throw new ArgumentException("Asigna la bodega de origen a una sucursal para elegir la fuente de traslados.");

        settings = ZeusRouting.Resolve(settings,reader.GetInt64(9),ZeusRouting.TransferMovement,reader.GetString(10));
        var origin = $"{reader.GetString(4)} · {reader.GetString(5)}";
        var destination = $"{reader.GetString(7)} · {reader.GetString(8)}";
        ZeusAccount WarehouseAccount(int offset,string concept,string warehouse)
        {
            if (reader.IsDBNull(offset) || reader.GetString(offset+1)!=settings.ServidorEsperado
                || reader.GetString(offset+2)!=settings.BaseEsperada
                || JsonSerializer.Deserialize<ZeusWarehouseAccounts>(reader.GetString(offset)) is not { } accounts
                || string.IsNullOrWhiteSpace(accounts.Inventario))
                throw new ArgumentException($"Configura la cuenta de inventario de la bodega {warehouse} para el destino Zeus actual.");
            return new(concept,accounts.Inventario,CentroCosto:accounts.CentroCosto??"");
        }

        var lines = reader.GetInt64(18);
        var amount = reader.GetDecimal(21);
        if (lines==0 || reader.GetInt64(19)!=lines || reader.GetInt64(20)!=lines)
            throw new ArgumentException("Faltan movimientos de salida o entrada del traslado en el Kardex.");
        if (amount<=0 || amount!=reader.GetDecimal(22))
            throw new ArgumentException("El costo de salida y de entrada del traslado debe coincidir y ser mayor que cero.");

        var date = reader.GetDateTime(1);
        var source = new ZeusSource(0,0,reader.GetString(0),date,date,date,amount,0,0,[]);
        return new(settings,source,new(0,"",""),[
            new(WarehouseAccount(15,"INVENTARIO_DESTINO",destination),amount,BodegaId:reader.GetInt64(6)),
            new(WarehouseAccount(12,"INVENTARIO_ORIGEN",origin),-amount,BodegaId:reader.GetInt64(3))
        ],Traslado:new(origin,destination,reader.IsDBNull(2)?null:reader.GetString(2)));
    }

    private static async Task<ZeusSnapshot> BuildTransferReversalAsync(SqlConnection connection, SqlTransaction transaction,
        long company, long reversal, long original, CancellationToken ct)
    {
        await using var query = Command(connection, """
            SELECT t.Numero,t.FechaContableRecepcion,t.Observacion,o.Numero,j.Estado,j.Snapshot,
                COALESCE(k.ValorEntrada,0),COALESCE(k.ValorSalida,0)
            FROM inv.Traslado t
            JOIN inv.Traslado o ON o.EmpresaId=t.EmpresaId AND o.TrasladoId=t.TrasladoOriginalId
            LEFT JOIN core.ZeusTrasladoEnvio j ON j.EmpresaId=o.EmpresaId AND j.TrasladoId=o.TrasladoId
            CROSS APPLY (
                SELECT SUM(md.ValorMovimiento) ValorEntrada,SUM(mo.ValorMovimiento) ValorSalida
                FROM inv.TrasladoLinea l
                JOIN inv.MovimientoInventario md ON md.EmpresaId=l.EmpresaId AND md.IdempotencyKey=l.EntradaDestinoKey
                    AND md.BodegaId=t.BodegaDestinoId AND md.TipoMovimiento='TRASLADO_ENTRADA'
                JOIN inv.MovimientoInventario mo ON mo.EmpresaId=l.EmpresaId AND mo.IdempotencyKey=l.SalidaOrigenKey
                    AND mo.BodegaId=t.BodegaOrigenId AND mo.TipoMovimiento='REVERSA_ENTRADA'
                WHERE l.EmpresaId=t.EmpresaId AND l.TrasladoId=t.TrasladoId
            ) k
            WHERE t.EmpresaId=@E AND t.TrasladoId=@Reversal AND o.TrasladoId=@Original;
            """, company, transaction);
        Add(query, "@Reversal", reversal);
        Add(query, "@Original", original);
        await using var row = await query.ExecuteReaderAsync(ct);
        if (!await row.ReadAsync(ct) || row.IsDBNull(1))
            throw new ArgumentException("No se encontró la reversión en el Kardex.");
        if (row.IsDBNull(4))
            throw new ArgumentException("El traslado original carece de comprobante registrado en Nexo. Verifica en Zeus antes de contabilizar la reversión.");
        if (row.GetString(4) != "CONTABILIZADO")
            throw new ArgumentException(WaitingForOriginalTransfer);
        if (row.IsDBNull(5) || JsonSerializer.Deserialize<ZeusSnapshot>(row.GetString(5)) is not { Traslado: { } originalRoute } posted)
            throw new ArgumentException("El comprobante original de Zeus carece del detalle necesario para preparar la reversión.");
        if (posted.Origen.Total != row.GetDecimal(6) || posted.Origen.Total != row.GetDecimal(7))
            throw new ArgumentException("El valor de la reversión en el Kardex debe coincidir con el comprobante original de Zeus.");

        var date = row.GetDateTime(1);
        var note = row.IsDBNull(2) ? null : row.GetString(2);
        var reversalSnapshot = posted with
        {
            Origen = posted.Origen with { Factura = row.GetString(0), FechaContable = date, FechaFactura = date, Vencimiento = date },
            Traslado = new(originalRoute.BodegaDestino, originalRoute.BodegaOrigen, $"Reversión de {row.GetString(3)}. {note}".Trim()),
            Movimientos = posted.Movimientos.Select(line => line with
            {
                Valor = -line.Valor,
                Regla = line.Regla with { Concepto = line.Valor > 0 ? "INVENTARIO_ORIGEN" : "INVENTARIO_DESTINO" }
            }).ToArray()
        };
        ZeusJournal.ValidateTransfer(reversalSnapshot);
        return reversalSnapshot;
    }
}
