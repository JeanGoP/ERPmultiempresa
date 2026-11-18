using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using NexoERP.Api.Data;
using NexoERP.Api.Inventory;

var database = "NexoKardexQa_" + Guid.NewGuid().ToString("N");
const string server = "Server=(localdb)\\MSSQLLocalDB;Integrated Security=True;TrustServerCertificate=True";
await using var admin = new SqlConnection(server + ";Database=master");
await admin.OpenAsync();
await using var command = admin.CreateCommand();
command.CommandText = $"CREATE DATABASE [{database}]";
await command.ExecuteNonQueryAsync();
try
{
    var connectionString = server + ";Database=" + database;
    await using (var connection = new SqlConnection(connectionString))
    {
        await connection.OpenAsync();
        await using var setup = connection.CreateCommand();
        setup.CommandText = """
            EXEC('CREATE SCHEMA inv');
            CREATE TABLE inv.Bodega(EmpresaId bigint,BodegaId bigint,Nombre nvarchar(120));
            CREATE TABLE inv.Articulo(EmpresaId bigint,ArticuloId bigint,Codigo nvarchar(50),Descripcion nvarchar(300));
            CREATE TABLE inv.Lote(EmpresaId bigint,LoteId bigint,NumeroLote nvarchar(100));
            CREATE TABLE inv.MovimientoInventario(
                EmpresaId bigint,MovimientoInventarioId bigint,FechaMovimiento datetime2,FechaContable date,
                TipoMovimiento varchar(30),NumeroDocumento nvarchar(50),BodegaId bigint,ArticuloId bigint,LoteId bigint NULL,
                CantidadEntrada decimal(20,6),CantidadSalida decimal(20,6),CostoUnitarioMovimiento decimal(20,8),
                ValorMovimiento decimal(20,4),ExistenciaPosterior decimal(20,6),CostoPromedioPosterior decimal(20,8),
                TipoDocumentoOrigen varchar(40),DocumentoOrigenId bigint,DocumentoLineaOrigenId bigint);
            CREATE TABLE inv.MovimientoInventarioUnidad(
                EmpresaId bigint,MovimientoInventarioId bigint,UnidadSerializadaId bigint,EstadoAnterior varchar(20) NULL,EstadoPosterior varchar(20));
            CREATE TABLE inv.UnidadIdentificador(EmpresaId bigint,UnidadSerializadaId bigint,Tipo varchar(20),Valor nvarchar(120));
            CREATE TABLE inv.RecepcionMercanciaLinea(EmpresaId bigint,RecepcionMercanciaId bigint,RecepcionMercanciaLineaId bigint);
            CREATE TABLE inv.RecepcionMercanciaUnidad(EmpresaId bigint,RecepcionMercanciaLineaId bigint,UnidadSerializadaId bigint);
            INSERT inv.Bodega VALUES(1,1,'Origen'),(1,2,'Destino'),(2,1,'Otra empresa');
            INSERT inv.Articulo VALUES(1,1,'DR150','Motocicleta DR150'),(1,2,'REP-1','Repuesto sin serial'),(2,1,'DR150','Motocicleta ajena');
            INSERT inv.UnidadIdentificador VALUES
                (1,11,'CHASIS','LC6-AAA'),(1,11,'VIN','LC6-AAA'),(1,11,'MOTOR','MOTOR-A'),(1,11,'PLACA','AAA01'),
                (1,12,'CHASIS','LC6-BBB'),(1,14,'CHASIS','OLD-CHASSIS'),(2,21,'CHASIS','LC6-AAA');
            INSERT inv.MovimientoInventario VALUES
                (1,1,'2026-11-01','2026-11-01','COMPRA','ENT-1',1,1,NULL,2,0,1000,2000,2,1000,'RECEPCION_MERCANCIA',1,1),
                (1,2,'2026-11-02','2026-11-02','TRASLADO_SALIDA','MOV-1',1,1,NULL,0,1,1000,1000,1,1000,'TRASLADO',1,1),
                (1,3,'2026-11-02','2026-11-02','TRASLADO_ENTRADA','MOV-1',2,1,NULL,1,0,1000,1000,1,1000,'TRASLADO',1,1),
                (1,4,'2026-11-03','2026-11-03','VENTA','FV-A',2,1,NULL,0,1,1000,1000,0,1000,'FACTURA_VENTA',1,1),
                (1,5,'2026-11-04','2026-11-04','DEVOLUCION_VENTA','DEV-A',2,1,NULL,1,0,1000,1000,1,1000,'DEVOLUCION_VENTA',1,1),
                (1,6,'2026-11-05','2026-11-05','REVERSA_ENTRADA','REV-A',2,1,NULL,0,1,1000,1000,0,1000,'REVERSA_MOVIMIENTO',1,1),
                (1,7,'2026-11-06','2026-11-06','VENTA','FV-B',1,1,NULL,0,1,1000,1000,0,1000,'FACTURA_VENTA',2,2),
                (1,8,'2026-10-01','2026-10-01','COMPRA','ENT-OLD',1,1,NULL,1,0,900,900,1,900,'RECEPCION_MERCANCIA',8,8),
                (2,9,'2026-11-01','2026-11-01','COMPRA','ENT-AJENA',1,1,NULL,1,0,1000,1000,1,1000,'RECEPCION_MERCANCIA',1,1),
                (1,10,'2026-11-07','2026-11-07','COMPRA','ENT-REP',1,2,NULL,5,0,100,500,5,100,'RECEPCION_MERCANCIA',10,10);
            INSERT inv.MovimientoInventarioUnidad VALUES
                (1,1,11,NULL,'DISPONIBLE'),(1,1,12,NULL,'DISPONIBLE'),
                (1,2,11,'DISPONIBLE','EN_TRANSITO'),(1,3,11,'EN_TRANSITO','DISPONIBLE'),
                (1,4,11,'DISPONIBLE','VENDIDA'),(1,5,11,'VENDIDA','DISPONIBLE'),
                (1,6,11,'DISPONIBLE','BAJA'),(1,7,12,'DISPONIBLE','VENDIDA'),(2,9,21,NULL,'DISPONIBLE');
            INSERT inv.RecepcionMercanciaLinea VALUES(1,1,1),(1,8,8);
            INSERT inv.RecepcionMercanciaUnidad VALUES(1,1,11),(1,1,12),(1,8,14);
            """;
        await setup.ExecuteNonQueryAsync();
    }
    var configuration = new ConfigurationBuilder()
        .AddInMemoryCollection(new Dictionary<string,string?> { ["ConnectionStrings:NexoErp"] = connectionString }).Build();
    var inventory = new InventoryRepository(new TenantConnectionFactory(configuration));
    async Task<IReadOnlyList<KardexMovementResponse>> Read(string? query = null, long? unit = null,
        long company = 1, DateOnly? from = null, long? warehouse = null) =>
        await inventory.GetKardexAsync(company,from,null,warehouse,null,query,default,unit);
    void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
        Console.WriteLine("OK: " + message);
    }

    var unfiltered = await Read();
    var sparePart = unfiltered.Single(row => row.MovimientoInventarioId == 10);
    Check(unfiltered.Count == 9 && sparePart.Unidades is { Count: 0 } && sparePart.Entrada == 5 && sparePart.ValorMovimiento == 500,
        "El Kardex general admite movimientos sin seriales y conserva sus cantidades e importes");
    Check((await Read("REP-1")).Single().Unidades is { Count: 0 },
        "La búsqueda de un artículo sin seriales devuelve una lista de unidades vacía");
    var general = await Read("DR150");
    var purchase = general.Single(row => row.MovimientoInventarioId == 1);
    Check(general.Count == 8 && purchase.Entrada == 2 && purchase.ValorMovimiento == 2000
        && purchase.Unidades?.Count == 2, "La consulta general conserva cantidades, importes y movimientos sin duplicarlos");
    var chassis = await Read("lc6-aaa");
    Check(chassis.Count == 6 && chassis.Select(row => row.MovimientoInventarioId).Distinct().Count() == 6,
        "El chasis encuentra compra, traslado, venta, devolución y reversión una sola vez");
    Check((await Read("motor-a")).Count == 6 && (await Read("aaa01")).Count == 6,
        "El mismo vehículo se encuentra por motor y placa");
    var history = await Read(unit:11);
    Check(history.Count == 6 && history.All(row => row.Unidades is { Count: 1 } && row.Unidades[0].UnidadSerializadaId == 11)
        && history[0].Unidades![0].EstadoPosterior == "BAJA", "La unidad conserva su historial aunque ya esté vendida o dada de baja");
    Check((await Read(unit:12)).Count == 2 && (await Read("lc6-aaa",unit:12)).Count == 0,
        "El historial de una moto excluye las operaciones de otra del mismo artículo");
    Check((await Read("lc6-aaa",company:2)).Count == 1 && (await Read(unit:21)).Count == 0,
        "Los identificadores compartidos entre empresas mantienen el aislamiento");
    var old = await Read("old-chassis");
    Check(old.Count == 1 && old[0].Unidades is { Count: 1 } && old[0].Unidades![0].UnidadSerializadaId == 14
        && (await Read(unit:14)).Count == 1, "La recepción histórica conserva el vehículo aunque preceda a la bitácora por unidad");
    Check((await Read(unit:11,from:new(2026,11,3),warehouse:2)).Count == 3,
        "Fechas y bodega se pueden aplicar al historial individual");
}
finally
{
    SqlConnection.ClearAllPools();
    command.CommandText = $"ALTER DATABASE [{database}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{database}]";
    await command.ExecuteNonQueryAsync();
}
