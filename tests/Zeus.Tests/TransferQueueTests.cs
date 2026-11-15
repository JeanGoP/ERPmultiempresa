using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using NexoERP.Api.Data;
using NexoERP.Api.Inventory;
using NexoERP.Api.Zeus;

static class TransferQueueTests
{
    public static async Task SqlAsync(ZeusSettings settings,Action<bool,string> check)
    {
        var database = "NexoTransferQueueTest_"+Guid.NewGuid().ToString("N");
        const string server = "Server=(localdb)\\MSSQLLocalDB;Integrated Security=True;TrustServerCertificate=True";
        await using var admin = new SqlConnection(server+";Database=master");
        await admin.OpenAsync();
        await using var setup = admin.CreateCommand();
        setup.CommandText = $"CREATE DATABASE [{database}]";
        await setup.ExecuteNonQueryAsync();
        try
        {
            var cs = server+";Database="+database;
            await using var connection = new SqlConnection(cs);
            await connection.OpenAsync();
            await using var command = connection.CreateCommand();
            async Task Run(string sql) { command.CommandText=sql; await command.ExecuteNonQueryAsync(); }
            async Task<object?> Scalar(string sql) { command.CommandText=sql; return await command.ExecuteScalarAsync(); }

            await Run("""
                EXEC('CREATE SCHEMA core'); EXEC('CREATE SCHEMA inv'); EXEC('CREATE SCHEMA seg'); EXEC('CREATE SCHEMA audit');
                CREATE TABLE core.SchemaMigration(MigrationId varchar(100) PRIMARY KEY,Descripcion nvarchar(250));
                CREATE TABLE core.Probe(EmpresaId bigint);
                CREATE TABLE core.Sucursal(EmpresaId bigint,SucursalId bigint,Nombre nvarchar(120));
                CREATE TABLE inv.Bodega(EmpresaId bigint,BodegaId bigint,Codigo nvarchar(30),Nombre nvarchar(120),SucursalId bigint);
                CREATE TABLE inv.Traslado(EmpresaId bigint,TrasladoId bigint,Numero nvarchar(50),Estado varchar(20),FechaContableRecepcion date NULL,
                    Observacion nvarchar(500),BodegaOrigenId bigint,BodegaDestinoId bigint,PRIMARY KEY(EmpresaId,TrasladoId));
                CREATE TABLE inv.TrasladoLinea(EmpresaId bigint,TrasladoId bigint,SalidaOrigenKey uniqueidentifier,EntradaDestinoKey uniqueidentifier);
                CREATE TABLE inv.MovimientoInventario(MovimientoInventarioId bigint IDENTITY,EmpresaId bigint,IdempotencyKey uniqueidentifier,
                    BodegaId bigint,TipoMovimiento varchar(30),ValorMovimiento decimal(20,4));
                CREATE TABLE core.ZeusConfiguracion(EmpresaId bigint,Configuracion nvarchar(max));
                CREATE TABLE core.ZeusBodegaCuenta(EmpresaId bigint,BodegaId bigint,Configuracion nvarchar(max),Servidor nvarchar(150),BaseDatos nvarchar(128));
                CREATE TABLE audit.Evento(EmpresaId bigint,UsuarioId bigint NULL,Operacion varchar(80),Entidad varchar(100),EntidadId nvarchar(100),
                    ValoresPosteriores nvarchar(max),AplicacionOrigen varchar(50));
                INSERT core.Sucursal VALUES(1,8,'Norte');
                INSERT inv.Bodega VALUES(1,11,'01','Origen',8),(1,12,'02','Destino',8);
                INSERT inv.Traslado VALUES(1,1,'MOV-001','DESPACHADO',NULL,N'Entrega en recepción',11,12),
                    (1,2,'MOV-002','DESPACHADO',NULL,NULL,11,12),(1,3,'MOV-003','DESPACHADO',NULL,NULL,11,12);
                INSERT inv.TrasladoLinea SELECT EmpresaId,TrasladoId,NEWID(),NEWID() FROM inv.Traslado;
                INSERT inv.MovimientoInventario SELECT EmpresaId,SalidaOrigenKey,11,'TRASLADO_SALIDA',125000.1234 FROM inv.TrasladoLinea;
                INSERT inv.MovimientoInventario SELECT EmpresaId,EntradaDestinoKey,12,'TRASLADO_ENTRADA',125000.1234 FROM inv.TrasladoLinea;
                """);
            await Run("""
                CREATE FUNCTION seg.fn_EmpresaAccess(@EmpresaId bigint) RETURNS TABLE WITH SCHEMABINDING AS
                    RETURN SELECT 1 AS Permitido WHERE @EmpresaId=TRY_CONVERT(bigint,SESSION_CONTEXT(N'EmpresaId'));
                """);
            await Run("CREATE SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.Probe;");
            var directory = new DirectoryInfo(AppContext.BaseDirectory);
            while(directory is not null && !Directory.Exists(Path.Combine(directory.FullName,"database","migrations"))) directory=directory.Parent;
            var migration = await File.ReadAllTextAsync(Path.Combine(directory!.FullName,"database","migrations","090_zeus_inventory_transfers.sql"));
            foreach (var batch in Regex.Split(migration,@"(?im)^\s*GO\s*$").Where(batch=>!string.IsNullOrWhiteSpace(batch))) await Run(batch);
            await Run("""
                CREATE PROCEDURE inv.usp_RecibirTraslado @EmpresaId bigint,@TrasladoId bigint,@PeriodoInventarioId bigint,
                    @FechaContable date,@FechaRecepcion datetime2,@UsuarioId bigint,@CorrelationId uniqueidentifier AS
                BEGIN
                    SET NOCOUNT ON; SET XACT_ABORT ON; BEGIN TRANSACTION;
                    DECLARE @Repeated bit=0;
                    UPDATE inv.Traslado SET Estado='RECIBIDO',FechaContableRecepcion=@FechaContable
                    WHERE EmpresaId=@EmpresaId AND TrasladoId=@TrasladoId AND Estado='DESPACHADO';
                    IF @@ROWCOUNT=0 SET @Repeated=1;
                    COMMIT;
                    SELECT @TrasladoId,'RECIBIDO',2,@Repeated;
                END;
                """);
            await Run("EXEC sys.sp_set_session_context @key=N'EmpresaId',@value=1;");
            var configured = settings with { FuentesAutomaticas = [new("Norte","TRASLADO","37","05",[],8)] };
            command.Parameters.AddWithValue("@Settings",JsonSerializer.Serialize(configured));
            command.Parameters.AddWithValue("@Server",settings.ServidorEsperado);
            command.Parameters.AddWithValue("@Db",settings.BaseEsperada);
            command.Parameters.AddWithValue("@Origin",JsonSerializer.Serialize(new ZeusWarehouseAccounts("143501","","","","","","",CentroCosto:"CC01")));
            command.Parameters.AddWithValue("@Destination",JsonSerializer.Serialize(new ZeusWarehouseAccounts("143502","","","","","","",CentroCosto:"CC02")));
            await Run("INSERT core.ZeusConfiguracion VALUES(1,@Settings); INSERT core.ZeusBodegaCuenta VALUES(1,11,@Origin,@Server,@Db),(1,12,@Destination,@Server,@Db);");
            command.Parameters.Clear();

            var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>{{"ConnectionStrings:NexoErp",cs}}).Build();
            var factory = new TenantConnectionFactory(configuration);
            var inventory = new InventoryOperationsRepository(factory);
            var zeus = new ZeusRepository(factory);
            var input = new PostTransferRequest(1,new DateOnly(2026,11,15),null,1,null);
            var accepted = await inventory.ReceiveTransferAsync(1,1,input,default);
            check(accepted.Zeus?.Estado=="PENDIENTE","Recibir en Nexo registra el envío Zeus en la misma operación");
            var snapshot = JsonSerializer.Deserialize<ZeusSnapshot>((string)(await Scalar("SELECT Snapshot FROM core.ZeusTrasladoEnvio WHERE TrasladoId=1"))!)!;
            check(snapshot.Configuracion.Fuente=="37" && snapshot.Traslado?.Observacion=="Entrega en recepción"
                && snapshot.Movimientos[0].Regla.Cuenta=="143502" && snapshot.Movimientos[0].Valor==125000.1234m
                && snapshot.Movimientos[1].Regla.Cuenta=="143501" && snapshot.Movimientos[1].Valor==-125000.1234m,
                "Comprobante toma la fuente de origen, la nota y el costo exacto del Kardex");
            check((await inventory.ReceiveTransferAsync(1,1,input,default)).YaExistia
                && (int)(await Scalar("SELECT COUNT(*) FROM core.ZeusTrasladoEnvio WHERE TrasladoId=1"))! == 1,"Recibir de nuevo no duplica el asiento");

            command.Parameters.AddWithValue("@Settings",JsonSerializer.Serialize(settings with { FuentesAutomaticas=[] }));
            await Run("UPDATE core.ZeusConfiguracion SET Configuracion=@Settings;");
            check((await inventory.ReceiveTransferAsync(1,2,input,default)).Zeus?.Estado=="REQUIERE_REVISION","Falta de fuente queda registrada para corregir en Zeus");
            command.Parameters["@Settings"].Value=JsonSerializer.Serialize(configured);
            await Run("UPDATE core.ZeusConfiguracion SET Configuracion=@Settings;");
            command.Parameters.Clear();
            var key = await Scalar("SELECT Clave FROM core.ZeusTrasladoEnvio WHERE TrasladoId=2");
            check((await zeus.RetryTransferAsync(1,2,1,default)).Estado=="PENDIENTE"
                && Equals(key,await Scalar("SELECT Clave FROM core.ZeusTrasladoEnvio WHERE TrasladoId=2")),"Reintentar tras corregir la configuración conserva la clave");

            await Run("CREATE TRIGGER core.FailTransferQueue ON core.ZeusTrasladoEnvio AFTER INSERT AS IF EXISTS(SELECT 1 FROM inserted WHERE TrasladoId=3) THROW 52996,'Fallo simulado de la cola',1;");
            try { await inventory.ReceiveTransferAsync(1,3,input,default); throw new Exception("Confirmó la recepción pese al fallo de la cola."); }
            catch(SqlException error) when(error.Number==52996)
            {
                check((string?)await Scalar("SELECT Estado FROM inv.Traslado WHERE TrasladoId=3")=="DESPACHADO","Si falla la cola, la recepción queda sin confirmar");
            }
        }
        finally
        {
            SqlConnection.ClearAllPools();
            setup.CommandText=$"ALTER DATABASE [{database}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{database}]";
            await setup.ExecuteNonQueryAsync();
        }
    }
}
