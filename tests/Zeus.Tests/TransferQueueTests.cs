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
                    Observacion nvarchar(500),BodegaOrigenId bigint,BodegaDestinoId bigint,TrasladoOriginalId bigint NULL,PRIMARY KEY(EmpresaId,TrasladoId));
                CREATE TABLE inv.TrasladoLinea(EmpresaId bigint,TrasladoId bigint,SalidaOrigenKey uniqueidentifier,EntradaDestinoKey uniqueidentifier);
                CREATE TABLE inv.MovimientoInventario(MovimientoInventarioId bigint IDENTITY,EmpresaId bigint,IdempotencyKey uniqueidentifier,
                    BodegaId bigint,TipoMovimiento varchar(30),ValorMovimiento decimal(20,4));
                CREATE TABLE core.ZeusConfiguracion(EmpresaId bigint,Configuracion nvarchar(max));
                CREATE TABLE core.ZeusBodegaCuenta(EmpresaId bigint,BodegaId bigint,Configuracion nvarchar(max),Servidor nvarchar(150),BaseDatos nvarchar(128));
                CREATE TABLE audit.Evento(EmpresaId bigint,UsuarioId bigint NULL,Operacion varchar(80),Entidad varchar(100),EntidadId nvarchar(100),
                    ValoresPosteriores nvarchar(max),AplicacionOrigen varchar(50));
                INSERT core.Sucursal VALUES(1,8,'Norte');
                INSERT inv.Bodega VALUES(1,11,'01','Origen',8),(1,12,'02','Destino',8);
                INSERT inv.Traslado VALUES(1,1,'MOV-001','BORRADOR',NULL,N'Entrega en recepción',11,12,NULL),
                    (1,2,'MOV-002','DESPACHADO',NULL,NULL,11,12,NULL),(1,3,'MOV-003','BORRADOR',NULL,NULL,11,12,NULL),
                    (1,4,'MOV-004','BORRADOR',NULL,NULL,11,12,NULL);
                INSERT inv.TrasladoLinea SELECT EmpresaId,TrasladoId,NEWID(),NEWID() FROM inv.Traslado;
                INSERT inv.MovimientoInventario SELECT EmpresaId,SalidaOrigenKey,11,'TRASLADO_SALIDA',125000.1234 FROM inv.TrasladoLinea;
                INSERT inv.MovimientoInventario SELECT EmpresaId,EntradaDestinoKey,12,'TRASLADO_ENTRADA',125000.1234 FROM inv.TrasladoLinea;
                """);
            await Run("""
                CREATE FUNCTION seg.fn_EmpresaAccess(@EmpresaId bigint) RETURNS TABLE WITH SCHEMABINDING AS
                    RETURN SELECT 1 AS Permitido WHERE @EmpresaId=TRY_CONVERT(bigint,SESSION_CONTEXT(N'EmpresaId'))
                        OR TRY_CONVERT(bit,SESSION_CONTEXT(N'BypassRls'))=1;
                """);
            await Run("CREATE SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.Probe;");
            var directory = new DirectoryInfo(AppContext.BaseDirectory);
            while(directory is not null && !Directory.Exists(Path.Combine(directory.FullName,"database","migrations"))) directory=directory.Parent;
            var migration = await File.ReadAllTextAsync(Path.Combine(directory!.FullName,"database","migrations","090_zeus_inventory_transfers.sql"));
            foreach (var batch in Regex.Split(migration,@"(?im)^\s*GO\s*$").Where(batch=>!string.IsNullOrWhiteSpace(batch))) await Run(batch);
            await Run("""
                CREATE PROCEDURE inv.usp_DespacharTraslado @EmpresaId bigint,@TrasladoId bigint,@PeriodoInventarioId bigint,
                    @FechaContable date,@UsuarioId bigint,@CorrelationId uniqueidentifier AS
                BEGIN
                    SET NOCOUNT ON; SET XACT_ABORT ON; BEGIN TRANSACTION;
                    DECLARE @Repeated bit=0;
                    UPDATE inv.Traslado SET Estado='DESPACHADO'
                    WHERE EmpresaId=@EmpresaId AND TrasladoId=@TrasladoId AND Estado='BORRADOR';
                    IF @@ROWCOUNT=0 SET @Repeated=1;
                    DECLARE @Estado varchar(20)=(SELECT Estado FROM inv.Traslado WHERE EmpresaId=@EmpresaId AND TrasladoId=@TrasladoId);
                    COMMIT;
                    SELECT @TrasladoId,@Estado,1,@Repeated;
                END;
                """);
            await Run("""
                CREATE PROCEDURE inv.usp_RecibirTraslado @EmpresaId bigint,@TrasladoId bigint,@PeriodoInventarioId bigint,
                    @FechaContable date,@FechaRecepcion datetime2,@UsuarioId bigint,@CorrelationId uniqueidentifier AS
                BEGIN
                    SET NOCOUNT ON; SET XACT_ABORT ON; BEGIN TRANSACTION;
                    IF NOT EXISTS(SELECT 1 FROM inv.Traslado WHERE EmpresaId=@EmpresaId AND TrasladoId=@TrasladoId AND Estado IN('DESPACHADO','RECIBIDO'))
                        THROW 51711,'El traslado debe estar despachado antes de recibirse.',1;
                    IF @TrasladoId=4 THROW 51712,'Fallo simulado de recepción.',1;
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
            var accepted = await inventory.CompleteTransferAsync(1,1,input,default);
            check(accepted.Estado=="RECIBIDO" && accepted.Movimientos==2 && accepted.Zeus?.Estado=="PENDIENTE",
                "Un solo traslado confirma el despacho, la recepción y la cola de Zeus");
            var snapshot = JsonSerializer.Deserialize<ZeusSnapshot>((string)(await Scalar("SELECT Snapshot FROM core.ZeusTrasladoEnvio WHERE TrasladoId=1"))!)!;
            check(snapshot.Configuracion.Fuente=="37" && snapshot.Traslado?.Observacion=="Entrega en recepción"
                && snapshot.Movimientos[0].Regla.Cuenta=="143502" && snapshot.Movimientos[0].Valor==125000.1234m
                && snapshot.Movimientos[1].Regla.Cuenta=="143501" && snapshot.Movimientos[1].Valor==-125000.1234m,
                "Comprobante toma la fuente de origen, la nota y el costo exacto del Kardex");
            var repeated = await inventory.CompleteTransferAsync(1,1,input,default);
            check(repeated.YaExistia && repeated.Zeus?.Estado=="PENDIENTE"
                && (int)(await Scalar("SELECT COUNT(*) FROM core.ZeusTrasladoEnvio WHERE TrasladoId=1"))! == 1,
                "Reintentar el traslado devuelve el estado del envío y no duplica el asiento");

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
            try { await inventory.CompleteTransferAsync(1,3,input,default); throw new Exception("Confirmó la recepción pese al fallo de la cola."); }
            catch(SqlException error) when(error.Number==52996)
            {
                check((string?)await Scalar("SELECT Estado FROM inv.Traslado WHERE TrasladoId=3")=="BORRADOR","Un fallo de cola revierte salida y entrada del traslado");
            }
            try { await inventory.CompleteTransferAsync(1,4,input,default); throw new Exception("Confirmó una recepción fallida."); }
            catch(SqlException error) when(error.Number==51712)
            {
                check((string?)await Scalar("SELECT Estado FROM inv.Traslado WHERE TrasladoId=4")=="BORRADOR"
                    && (int)(await Scalar("SELECT COUNT(*) FROM core.ZeusTrasladoEnvio WHERE TrasladoId=4"))! == 0,
                    "Un fallo en destino revierte la salida y no genera envío a Zeus");
            }

            await Run("""
                UPDATE inv.Traslado SET Estado='REVERTIDO' WHERE TrasladoId=1;
                INSERT inv.Traslado VALUES(1,5,'REV-001','RECIBIDO','2026-11-16',N'Error de bodega',12,11,1);
                INSERT inv.TrasladoLinea VALUES(1,5,NEWID(),NEWID());
                INSERT inv.MovimientoInventario SELECT EmpresaId,SalidaOrigenKey,12,'REVERSA_ENTRADA',125000.1234
                    FROM inv.TrasladoLinea WHERE TrasladoId=5;
                INSERT inv.MovimientoInventario SELECT EmpresaId,EntradaDestinoKey,11,'TRASLADO_ENTRADA',125000.1234
                    FROM inv.TrasladoLinea WHERE TrasladoId=5;
                """);
            await using (var transaction = (SqlTransaction)await connection.BeginTransactionAsync())
            {
                var waiting = await ZeusRepository.EnqueueTransferAsync(connection,transaction,1,5,1,default);
                check(waiting.Estado=="REQUIERE_REVISION" && waiting.Mensaje.Contains("original"),
                    "La reversión espera la contabilización del traslado original en Zeus");
                await transaction.CommitAsync();
            }
            await zeus.PrepareWaitingTransferReversalAsync(default);
            check((await zeus.TransferStatusAsync(1,5,default)).Estado=="REQUIERE_REVISION",
                "La reversión no se envía si el original todavía está pendiente");
            await Run("""
                UPDATE core.ZeusBodegaCuenta SET Configuracion=N'{}';
                UPDATE core.ZeusTrasladoEnvio SET Estado='CONTABILIZADO',Fuente='37',Documento='0000000501' WHERE TrasladoId=1;
                """);
            await zeus.PrepareWaitingTransferReversalAsync(default);
            var reversalSnapshot = JsonSerializer.Deserialize<ZeusSnapshot>((string)(await Scalar("SELECT Snapshot FROM core.ZeusTrasladoEnvio WHERE TrasladoId=5"))!)!;
            check((await zeus.TransferStatusAsync(1,5,default)).Estado=="PENDIENTE"
                && reversalSnapshot.Origen.FechaContable==new DateTime(2026,11,16)
                && reversalSnapshot.Traslado?.BodegaOrigen==snapshot.Traslado?.BodegaDestino
                && reversalSnapshot.Movimientos[0].Regla.Concepto=="INVENTARIO_ORIGEN"
                && reversalSnapshot.Movimientos[0].Regla.Cuenta=="143502" && reversalSnapshot.Movimientos[0].Regla.CentroCosto=="CC02"
                && reversalSnapshot.Movimientos[0].Valor==-125000.1234m
                && reversalSnapshot.Movimientos[1].Regla.Cuenta=="143501" && reversalSnapshot.Movimientos[1].Valor==125000.1234m,
                "La reversión invierte las partidas originales sin depender del mapeo actualizado");
        }
        finally
        {
            SqlConnection.ClearAllPools();
            setup.CommandText=$"ALTER DATABASE [{database}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{database}]";
            await setup.ExecuteNonQueryAsync();
        }
    }
}
