using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;

namespace NexoERP.Api.CrmIntegration;

public sealed record CrmCreditCustomer(string IdentificationType, string IdentificationNumber, string Name, string? Phone);
public sealed record CrmCreditItem(string Reference, string Name, decimal Price, int Quantity);
public sealed record CrmApprovedCreditInput(
    Guid EventId, Guid CrmCompanyId, long ErpCompanyId, string CompanyNit, Guid ApplicationId, string ApplicationNumber,
    DateTime ApprovedAtUtc, CrmCreditCustomer Customer, CrmCreditItem[] Items,
    decimal ApprovedAmount, decimal DownPayment, decimal FinancedAmount, int TermMonths, DateTime? FirstDueDate,
    string? Advisor, string? SalesPoint);
public sealed record CrmCreditReceipt(long ReceiptId, string Status, bool AlreadyReceived);
public sealed record CrmAvailableCompany(long Id, string Name, string Nit);
public sealed record CrmCreditPending(long ReceiptId, Guid ApplicationId, string ApplicationNumber,
    string CustomerName, string CustomerIdentification, decimal ApprovedAmount, string Status, DateTime ReceivedUtc);

public sealed class CrmApprovedCreditRepository(TenantConnectionFactory connections)
{
    public async Task<IReadOnlyList<CrmAvailableCompany>> AvailableCompaniesAsync(string allowedNit, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(null, true, ct);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT EmpresaId, RazonSocial, CONCAT(Nit, COALESCE('-' + DigitoVerificacion, ''))
            FROM core.Empresa
            WHERE Activa = 1
              AND CONCAT(REPLACE(REPLACE(REPLACE(Nit, '-', ''), '.', ''), ' ', ''),
                         COALESCE(DigitoVerificacion, '')) = @Nit;
            """;
        command.Parameters.Add(new SqlParameter("@Nit", SqlDbType.NVarChar, 20) { Value = Digits(allowedNit) });
        var rows = new List<CrmAvailableCompany>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
            rows.Add(new CrmAvailableCompany(reader.GetInt64(0), reader.GetString(1), reader.GetString(2)));
        return rows;
    }

    public async Task<IReadOnlyList<CrmCreditPending>> ListAsync(long empresaId, CancellationToken ct)
    {
        await using var connection = await connections.OpenAsync(empresaId, false, ct);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT TOP (100) ReceiptId, ApplicationId, ApplicationNumber,
                JSON_VALUE(PayloadJson, '$.customer.name'),
                JSON_VALUE(PayloadJson, '$.customer.identificationNumber'),
                TRY_CONVERT(decimal(18,2), JSON_VALUE(PayloadJson, '$.approvedAmount')),
                Status, ReceivedUtc
            FROM ven.CrmApprovedCredit
            WHERE EmpresaId = @EmpresaId
            ORDER BY ReceivedUtc DESC, ReceiptId DESC;
            """;
        command.Parameters.Add(new SqlParameter("@EmpresaId", SqlDbType.BigInt) { Value = empresaId });
        var rows = new List<CrmCreditPending>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
            rows.Add(new CrmCreditPending(reader.GetInt64(0), reader.GetGuid(1), reader.GetString(2),
                reader.IsDBNull(3) ? "" : reader.GetString(3),
                reader.IsDBNull(4) ? "" : reader.GetString(4),
                reader.IsDBNull(5) ? 0 : reader.GetDecimal(5), reader.GetString(6), reader.GetDateTime(7)));
        return rows;
    }

    public async Task<CrmCreditReceipt?> ReceiveAsync(CrmApprovedCreditInput input, CancellationToken ct)
    {
        await using var lookup = await connections.OpenAsync(null, true, ct);
        await using var company = lookup.CreateCommand();
        company.CommandText = """
            SELECT EmpresaId FROM core.Empresa
            WHERE Activa = 1 AND EmpresaId = @ErpCompanyId
              AND CONCAT(REPLACE(REPLACE(REPLACE(Nit, '-', ''), '.', ''), ' ', ''),
                         COALESCE(DigitoVerificacion, '')) = @Nit;
            """;
        company.Parameters.Add(new SqlParameter("@ErpCompanyId", SqlDbType.BigInt) { Value = input.ErpCompanyId });
        company.Parameters.Add(new SqlParameter("@Nit", SqlDbType.NVarChar, 20) { Value = Digits(input.CompanyNit) });
        var value = await company.ExecuteScalarAsync(ct);
        if (value is null) return null;
        var empresaId = Convert.ToInt64(value);

        var payload = JsonSerializer.Serialize(input, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(payload)));
        await using var connection = await connections.OpenAsync(empresaId, false, ct);
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(IsolationLevel.Serializable, ct);
        await using var existing = connection.CreateCommand();
        existing.Transaction = transaction;
        existing.CommandText = """
            SELECT ReceiptId, PayloadHash, Status FROM ven.CrmApprovedCredit WITH (UPDLOCK, HOLDLOCK)
            WHERE EmpresaId = @EmpresaId AND (ApplicationId = @ApplicationId OR EventId = @EventId);
            """;
        existing.Parameters.Add(new SqlParameter("@EmpresaId", SqlDbType.BigInt) { Value = empresaId });
        existing.Parameters.Add(new SqlParameter("@ApplicationId", SqlDbType.UniqueIdentifier) { Value = input.ApplicationId });
        existing.Parameters.Add(new SqlParameter("@EventId", SqlDbType.UniqueIdentifier) { Value = input.EventId });
        await using (var reader = await existing.ExecuteReaderAsync(ct))
        {
            if (await reader.ReadAsync(ct))
            {
                var result = new CrmCreditReceipt(reader.GetInt64(0), reader.GetString(2), true);
                if (!string.Equals(reader.GetString(1), hash, StringComparison.Ordinal))
                    throw new InvalidOperationException("La solicitud del CRM ya fue recibida con datos diferentes.");
                await reader.CloseAsync();
                await transaction.CommitAsync(ct);
                return result;
            }
        }

        await using var insert = connection.CreateCommand();
        insert.Transaction = transaction;
        insert.CommandText = """
            INSERT ven.CrmApprovedCredit
                (EmpresaId, EventId, CrmCompanyId, ApplicationId, ApplicationNumber, PayloadJson, PayloadHash)
            OUTPUT INSERTED.ReceiptId
            VALUES (@EmpresaId, @EventId, @CrmCompanyId, @ApplicationId, @ApplicationNumber, @PayloadJson, @PayloadHash);
            """;
        insert.Parameters.Add(new SqlParameter("@EmpresaId", SqlDbType.BigInt) { Value = empresaId });
        insert.Parameters.Add(new SqlParameter("@EventId", SqlDbType.UniqueIdentifier) { Value = input.EventId });
        insert.Parameters.Add(new SqlParameter("@CrmCompanyId", SqlDbType.UniqueIdentifier) { Value = input.CrmCompanyId });
        insert.Parameters.Add(new SqlParameter("@ApplicationId", SqlDbType.UniqueIdentifier) { Value = input.ApplicationId });
        insert.Parameters.Add(new SqlParameter("@ApplicationNumber", SqlDbType.NVarChar, 40) { Value = input.ApplicationNumber });
        insert.Parameters.Add(new SqlParameter("@PayloadJson", SqlDbType.NVarChar, -1) { Value = payload });
        insert.Parameters.Add(new SqlParameter("@PayloadHash", SqlDbType.Char, 64) { Value = hash });
        var receiptId = Convert.ToInt64(await insert.ExecuteScalarAsync(ct));
        await transaction.CommitAsync(ct);
        return new CrmCreditReceipt(receiptId, "PENDIENTE_REVISION", false);
    }

    public static string Digits(string value) => new(value.Where(char.IsDigit).ToArray());
}
