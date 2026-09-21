using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using NexoERP.Api.Data;
using NexoERP.Api.Zeus;
using System.Text.Json;

static class WarehouseAccountsTests
{
    public static async Task Run(string cs,ZeusSettings settings,ZeusSource source,ZeusPreviewRequest input,Action<bool,string> check)
    {
        await using var c=new SqlConnection(cs);await c.OpenAsync();await using var q=c.CreateCommand();
        q.CommandText="ALTER TABLE dbo.MAECONT ADD DESCCTA varchar(40);EXEC('UPDATE dbo.MAECONT SET DESCCTA=CODICTA');EXEC('INSERT dbo.MAECONT VALUES(''GRUPO'',1,''G'',1,''Grupo''),(''INACTIVA'',0,''D'',1,''Inactiva''),(''BANCO'',1,''D'',6,''Banco'')');";await q.ExecuteNonQueryAsync();
        q.CommandText="CREATE PROCEDURE dbo.SpMae_Maecont @Op varchar(30) AS BEGIN IF @Op<>'A' THROW 51999,'Solo lectura',1; SELECT * FROM dbo.MAECONT; RETURN 0; END";await q.ExecuteNonQueryAsync();
        var config=new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>{["ConnectionStrings:NexoErp"]=cs,["Zeus:Companies:1:ConnectionString"]=cs}).Build();
        var transport=new ZeusTransport(config);
        var destination=settings with{ServidorEsperado=c.DataSource,BaseEsperada=c.Database};
        var chart=await transport.ChartAsync(1,destination,default);
        check(chart.Length==3&&chart.All(a=>a.Nombre==a.Codigo),"Plan usa opción A y filtra grupos, inactivas, cartera y bancos");
        try{await transport.ChartAsync(2,destination,default);throw new Exception("Compartió conexión");}catch(ArgumentException){check(true,"Plan no reutiliza conexión de otra empresa");}
        var accounts=new ZeusWarehouseAccounts("1435","2408","2408","2408","1435","1435","1435");accounts.Validate(chart);
        try{(accounts with{Ingreso="999"}).Validate(chart);throw new Exception("Aceptó cuenta inexistente");}catch(ArgumentException){check(true,"Valida las siete cuentas contra plan Zeus");}
        var repo=new ZeusWarehouseRepository(new TenantConnectionFactory(config));
        var saved=new ZeusWarehouseSave(0,1,accounts);
        check((await repo.GetAsync(1,1,default)).Version==0,"Bodega sin configurar no inventa cuentas");
        try{await repo.GetAsync(1,3,default);throw new Exception("Leyó bodega ajena");}catch(ArgumentException){check(true,"Bodega ajena rechazada");}
        try{await repo.SaveAsync(1,1,1,saved,new(1,settings),default);throw new Exception("Cambió con incierto");}catch(SqlException e)when(e.Number==51701){check(true,"Cuentas bloqueadas durante envío incierto");}
        q.CommandText="EXEC sys.sp_set_session_context @key=N'EmpresaId',@value=1;UPDATE core.ZeusEnvio SET Estado='RECHAZADO';";await q.ExecuteNonQueryAsync();
        await repo.SaveAsync(1,1,1,saved,new(1,settings),default);
        var stored=await repo.GetAsync(1,1,default);check(stored.Version==1&&stored.Cuentas==accounts,"Guarda siete cuentas de la bodega en ERP");
        try{await repo.SaveAsync(1,1,1,saved,new(1,settings),default);throw new Exception("Aceptó versión vieja");}catch(SqlException e)when(e.Number==51702){check(true,"Evita sobrescribir cambios concurrentes");}
        q.CommandText="EXEC sys.sp_set_session_context @key=N'EmpresaId',@value=2;SELECT COUNT(*) FROM core.ZeusBodegaCuenta";
        check(Convert.ToInt32(await q.ExecuteScalarAsync())==0,"RLS oculta configuración de bodegas ajenas");
        var posting=new ZeusRepository(new TenantConnectionFactory(config));
        var preview=JsonSerializer.SerializeToElement(await posting.PreviewAsync(1,20,input,default));
        var snapshot=preview.GetProperty("comprobante").Deserialize<ZeusSnapshot>()!;
        check(snapshot.Origen.Lineas[0].BodegaId==1&&snapshot.Movimientos[0].Regla.Cuenta=="1435","Repositorio usa bodega de entrada y sus cuentas");
        check(await posting.EligibleAsync(1,snapshot,default),"Worker reconstruye comprobante con cuentas de bodega");
        q.CommandText="EXEC sys.sp_set_session_context @key=N'EmpresaId',@value=1;UPDATE inv.RecepcionMercanciaLinea SET BodegaId=2;";await q.ExecuteNonQueryAsync();
        check(!await posting.EligibleAsync(1,snapshot,default),"Bodega por línea sin configurar bloquea envío");
        q.CommandText="UPDATE inv.RecepcionMercanciaLinea SET BodegaId=NULL;UPDATE core.ZeusBodegaCuenta SET BaseDatos='OTRA';";await q.ExecuteNonQueryAsync();
        check(!await posting.EligibleAsync(1,snapshot,default),"Cambio de destino exige revalidar cuentas");
        q.CommandText="DELETE core.ZeusBodegaCuenta;";await q.ExecuteNonQueryAsync();
        var split=source with{Lineas=[new(50,40,1,"143501","240801"),new(50,60,2,"143502","240802")]};
        var taxes=input with{Impuestos=[new("IVA",19,40,7.6m,1),new("IVA",19,60,11.4m,2)]};
        var journal=ZeusJournal.Build(settings,split,taxes);
        check(journal.Movimientos[0].Regla.Cuenta=="143501"&&journal.Movimientos[1].Regla.Cuenta=="143502"&&journal.Movimientos.Sum(m=>m.Valor)==0,"Inventario del mismo artículo usa bodega por línea, sin alterar totales");
        check(journal.Movimientos[2].Regla.Cuenta=="240801"&&journal.Movimientos[3].Regla.Cuenta=="240802","IVA distribuido conserva cuentas y base por bodega");
        try{ZeusJournal.Build(settings,split,input);throw new Exception("Distribuyó arbitrariamente");}catch(ArgumentException){check(true,"IVA ambiguo exige distribución explícita");}
        try{ZeusJournal.Build(settings,split,input with{Impuestos=[new("IVA",19,100,19,99)]});throw new Exception("Aceptó bodega ajena a entrada");}catch(ArgumentException){check(true,"IVA rechaza bodega que no participa en entrada");}
        try{ZeusJournal.Build(settings,split,input with{Impuestos=[new("IVA",19,100,19,1)]});throw new Exception("Aceptó base mayor");}catch(ArgumentException){check(true,"IVA rechaza base superior a mercancía de la bodega");}
    }
}
