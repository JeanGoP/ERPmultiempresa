using System.Data;
using Microsoft.Data.SqlClient;

namespace NexoERP.Api.Data;

public sealed class TenantConnectionFactory(IConfiguration configuration)
{
    private readonly string _connectionString = configuration.GetConnectionString("NexoErp")
        ?? throw new InvalidOperationException("Falta ConnectionStrings:NexoErp.");

    public async Task<SqlConnection> OpenAsync(long? empresaId, bool bypassRls, CancellationToken cancellationToken)
    {
        var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        try
        {
            await using var context = connection.CreateCommand();
            context.CommandText = """
                EXEC sys.sp_set_session_context @key=N'EmpresaId', @value=NULL;
                EXEC sys.sp_set_session_context @key=N'BypassRls', @value=NULL;
                EXEC sys.sp_set_session_context @key=N'EmpresaId', @value=@EmpresaId;
                EXEC sys.sp_set_session_context @key=N'BypassRls', @value=@BypassRls;
                """;
            context.Parameters.Add(new SqlParameter("@EmpresaId", SqlDbType.BigInt) { Value = empresaId is null ? DBNull.Value : empresaId.Value });
            context.Parameters.Add(new SqlParameter("@BypassRls", SqlDbType.Bit) { Value = bypassRls });
            await context.ExecuteNonQueryAsync(cancellationToken);
            return connection;
        }
        catch
        {
            await connection.DisposeAsync();
            throw;
        }
    }
}
