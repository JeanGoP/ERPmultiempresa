using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;

namespace NexoERP.Api.Zeus;

internal sealed record ZeusTransferJob(long Company, long Transfer, Guid Key, ZeusSnapshot Snapshot);

public sealed partial class ZeusRepository
{
    public async Task<ZeusPostingStatus> TransferStatusAsync(long company, long transfer, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(company, false, ct);
        await using var query = Command(connection, """
            SELECT Estado,Error,Fuente,Documento
            FROM core.ZeusTrasladoEnvio WHERE EmpresaId=@E AND TrasladoId=@Transfer;
            """, company);
        Add(query, "@Transfer", transfer);
        await using var row = await query.ExecuteReaderAsync(ct);
        if (!await row.ReadAsync(ct))
            return new("SIN_ENVIO", "No hay envío a Zeus registrado para este traslado.");

        var state = row.GetString(0);
        var message = state switch
        {
            "PENDIENTE" => "Traslado recibido en Nexo. Pendiente de contabilizar en Zeus.",
            "ENVIANDO" => "Traslado recibido en Nexo. Enviando comprobante a Zeus.",
            "CONTABILIZADO" when !row.IsDBNull(2) && !row.IsDBNull(3) => $"Traslado contabilizado en Zeus. Comprobante {row.GetString(2)} {row.GetString(3)}.",
            _ => row.IsDBNull(1) ? $"Estado del comprobante en Zeus: {state}." : row.GetString(1)
        };
        return new(state, message);
    }

    public async Task<ZeusPostingStatus> RetryTransferAsync(long company, long transfer, long user, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(company, false, ct);
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(IsolationLevel.Serializable, ct);
        await using var query = Command(connection, """
            SELECT TrasladoId FROM inv.Traslado WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND TrasladoId=@Transfer;
            """, company, transaction);
        Add(query, "@Transfer", transfer);
        if (await query.ExecuteScalarAsync(ct) is null)
            throw new ArgumentException("El traslado no existe en esta empresa.");
        query.CommandText = """
            SELECT Estado FROM core.ZeusTrasladoEnvio WITH(UPDLOCK,HOLDLOCK)
            WHERE EmpresaId=@E AND TrasladoId=@Transfer;
            """;
        var state = await query.ExecuteScalarAsync(ct) as string;
        if (state is not ("REQUIERE_REVISION" or "RECHAZADO"))
            throw new ArgumentException("Solo se puede reintentar un traslado rechazado o pendiente de corregir en Zeus.");

        var status = await EnqueueTransferAsync(connection, transaction, company, transfer, user, ct);
        await transaction.CommitAsync(ct);
        return status;
    }

    internal async Task<ZeusTransferJob?> ClaimTransferAsync(CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(null, true, ct);
        await using var query = connection.CreateCommand();
        query.CommandText = """
            SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
            UPDATE core.ZeusTrasladoEnvio
            SET Estado='INCIERTO',Error=N'Envío interrumpido. Concilia en Zeus antes de reenviar.',ActualizadoEnUtc=SYSUTCDATETIME()
            WHERE Estado='ENVIANDO' AND ActualizadoEnUtc<DATEADD(minute,-15,SYSUTCDATETIME());
            ;WITH siguiente AS (
                SELECT TOP(1) * FROM core.ZeusTrasladoEnvio WITH(UPDLOCK,READPAST,READCOMMITTEDLOCK)
                WHERE Estado='PENDIENTE' ORDER BY CreadoEnUtc,EmpresaId,TrasladoId
            )
            UPDATE siguiente SET Estado='ENVIANDO',Intentos=Intentos+1,ActualizadoEnUtc=SYSUTCDATETIME()
            OUTPUT inserted.EmpresaId,inserted.TrasladoId,inserted.Clave,inserted.Snapshot;
            """;
        await using var row = await query.ExecuteReaderAsync(ct);
        if (!await row.ReadAsync(ct)) return null;
        return new(row.GetInt64(0), row.GetInt64(1), row.GetGuid(2), JsonSerializer.Deserialize<ZeusSnapshot>(row.GetString(3))!);
    }

    internal async Task<ZeusTransferJob> UncertainTransferAsync(long company, long transfer, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(company, false, ct);
        await using var query = Command(connection, """
            SELECT Clave,Snapshot FROM core.ZeusTrasladoEnvio
            WHERE EmpresaId=@E AND TrasladoId=@Transfer AND Estado='INCIERTO';
            """, company);
        Add(query, "@Transfer", transfer);
        await using var row = await query.ExecuteReaderAsync(ct);
        if (!await row.ReadAsync(ct))
            throw new ArgumentException("No hay un envío incierto para este traslado.");
        return new(company, transfer, row.GetGuid(0), JsonSerializer.Deserialize<ZeusSnapshot>(row.GetString(1))!);
    }

    internal async Task FinishTransferAsync(ZeusTransferJob job, ZeusResult result, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(job.Company, false, ct);
        await using var query = Command(connection, """
            SET XACT_ABORT ON;
            BEGIN TRANSACTION;
            UPDATE core.ZeusTrasladoEnvio
            SET Estado=@State,Fuente=@Source,Documento=@Document,Error=@Error,ActualizadoEnUtc=SYSUTCDATETIME()
            WHERE EmpresaId=@E AND TrasladoId=@Transfer AND Clave=@Key AND Estado IN('ENVIANDO','INCIERTO');
            IF @@ROWCOUNT=1
                INSERT audit.Evento(EmpresaId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
                VALUES(@E,'ZEUS_RESULTADO_TRASLADO','inv.Traslado',CONVERT(nvarchar(100),@Transfer),
                    (SELECT @State estado,@Source fuente,@Document documento,@Error error FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),'ZEUS');
            COMMIT;
            """, job.Company);
        Add(query, "@Transfer", job.Transfer);
        Add(query, "@Key", job.Key);
        Add(query, "@State", result.Estado);
        Add(query, "@Source", (object?)result.Fuente ?? DBNull.Value);
        Add(query, "@Document", (object?)result.Documento ?? DBNull.Value);
        var error = result.Error;
        Add(query, "@Error", error is null ? DBNull.Value : error[..Math.Min(error.Length, 2000)]);
        await query.ExecuteNonQueryAsync(ct);
    }
}

public sealed class ZeusTransferWorker(IServiceScopeFactory scopes, IConfiguration configuration, ILogger<ZeusTransferWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if (configuration.GetValue<bool>("Zeus:Enabled"))
                {
                    using var scope = scopes.CreateScope();
                    var repository = scope.ServiceProvider.GetRequiredService<ZeusRepository>();
                    var job = await repository.ClaimTransferAsync(stoppingToken);
                    if (job is not null)
                    {
                        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
                        deadline.CancelAfter(TimeSpan.FromMinutes(3));
                        var settings = await repository.SettingsAsync(job.Company, deadline.Token);
                        var transport = scope.ServiceProvider.GetRequiredService<ZeusTransport>();
                        var result = settings?.Configuracion.Habilitado == true
                            ? await transport.SendAsync(job.Company, job.Snapshot, job.Key, deadline.Token)
                            : new ZeusResult("RECHAZADO", Error:"Activa la integración Zeus de esta empresa y reintenta el comprobante.");
                        using var finish = new CancellationTokenSource(TimeSpan.FromSeconds(15));
                        await repository.FinishTransferAsync(job, result, finish.Token);
                    }
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception error)
            {
                logger.LogWarning("El despachador de traslados a Zeus requiere revisión ({Type}).", error.GetType().Name);
            }
            try { await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken); }
            catch (OperationCanceledException) { break; }
        }
    }
}
